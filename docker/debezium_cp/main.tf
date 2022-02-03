terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
      version = "~> 2.13.0"
    }
  }
}

provider "docker" {}

resource "docker_network" "debezium_cp" {
  name = "debezium_cp_default"
}

resource "docker_image" "zookeeper" {
  name = "confluentinc/cp-zookeeper:${var.cp_version}"
  keep_locally = true
}

resource "docker_container" "zookeeper" {
  image = docker_image.zookeeper.latest
  name  = "zookeeper"
  hostname = "zookeeper"
  ports {
    internal = 2181
    external = 2181
  }
  env = ["ZOOKEEPER_CLIENT_PORT=2181", "ZOOKEEPER_TICK_TIME=2000"]
  restart = "no"
  must_run = "true"
  network_mode= "${docker_network.debezium_cp.name}"
}

resource "docker_image" "broker" {
  name = "confluentinc/cp-server:${var.cp_version}"
  keep_locally = true
}

resource "docker_container" "broker" {
  image = docker_image.broker.latest
  name  = "broker"
  hostname = "broker"
  depends_on = [docker_container.zookeeper]
  ports {
    internal = 9092
    external = 9092
  }
  ports {
    internal = 9101
    external = 9930
  }
  env = [ "KAFKA_BROKER_ID=1", 
      "KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181",
      "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT",
      "KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://broker:29092,PLAINTEXT_HOST://localhost:9092",
      "KAFKA_METRIC_REPORTERS=io.confluent.metrics.reporter.ConfluentMetricsReporter",
      "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1",
      "KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0",
      "KAFKA_CONFLUENT_LICENSE_TOPIC_REPLICATION_FACTOR=1",
      "KAFKA_CONFLUENT_BALANCER_TOPIC_REPLICATION_FACTOR=1",
      "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1",
      "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1",
      "KAFKA_JMX_PORT=9101",
      "KAFKA_JMX_HOSTNAME=localhost",
      "KAFKA_CONFLUENT_SCHEMA_REGISTRY_URL=http://schema-registry:8081",
      "CONFLUENT_METRICS_REPORTER_BOOTSTRAP_SERVERS=broker:29092",
      "CONFLUENT_METRICS_REPORTER_TOPIC_REPLICAS=1",
      "CONFLUENT_METRICS_ENABLE=true",
      "CONFLUENT_SUPPORT_CUSTOMER_ID=anonymous"]
  restart = "no"
  must_run = "true"
  network_mode= "${docker_network.debezium_cp.name}"
}

resource "docker_image" "schema-registry" {
  name = "confluentinc/cp-schema-registry:${var.cp_version}"
  keep_locally = true
}

resource "docker_container" "schema-registry" {
  image = docker_image.schema-registry.latest
  name  = "schema-registry"
  hostname = "schema-registry"
  depends_on = [docker_container.broker]
  ports {
    internal = 8081
    external = 8081
  }
  env = ["SCHEMA_REGISTRY_HOST_NAME=schema-registry",
      "SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS=broker:29092",
      "SCHEMA_REGISTRY_LISTENERS=http://0.0.0.0:8081"]
  restart = "no"
  must_run = "true"
  network_mode= "${docker_network.debezium_cp.name}"
}

resource "docker_image" "mysql" {
  name = "debezium/example-mysql:${var.debezium_version}"
  keep_locally = true
}

resource "docker_container" "mysql" {
  image = docker_image.mysql.latest
  name  = "mysql"
  hostname = "mysql"
  ports {
    internal = 3306
    external = 3306
  }
  # volumes for dumping and exporting tables
  volumes {
    host_path = "${path.cwd}/padogrid"
    container_path = "/padogrid"
  }
  env = ["MYSQL_ROOT_PASSWORD=debezium",
      "MYSQL_USER=mysqluser",
      "MYSQL_PASSWORD=mysqlpw"]
  restart = "no"
  must_run = "true"
  network_mode= "${docker_network.debezium_cp.name}"
}

resource "docker_image" "connect" {
  name = "cnfldemos/cp-server-connect-datagen:0.5.0-6.2.0"
  keep_locally = true
}

resource "docker_container" "connect" {
  image = docker_image.connect.latest
  name  = "connect"
  hostname = "connect"
  ports {
    internal = 8083
    external = 8083
  }
  volumes {
    host_path = "${path.cwd}/padogrid"
    container_path = "/padogrid"
  }

  # CLASSPATH required due to CC-2422
  env = ["CONNECT_BOOTSTRAP_SERVERS=broker:29092",
      "CONNECT_REST_ADVERTISED_HOST_NAME=connect",
      "CONNECT_GROUP_ID=compose-connect-group",
      "CONNECT_CONFIG_STORAGE_TOPIC=docker-connect-configs",
      "CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR=1",
      "CONNECT_OFFSET_FLUSH_INTERVAL_MS=10000",
      "CONNECT_OFFSET_STORAGE_TOPIC=docker-connect-offsets",
      "CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR=1",
      "CONNECT_STATUS_STORAGE_TOPIC=docker-connect-status",
      "CONNECT_STATUS_STORAGE_REPLICATION_FACTOR=1",
      "CONNECT_KEY_CONVERTER_SCHEMA_REGISTRY_URL=http://schema-registry:8081",
      "CONNECT_KEY_CONVERTER=io.confluent.connect.avro.AvroConverter",
      "CONNECT_VALUE_CONVERTER=io.confluent.connect.avro.AvroConverter",
      "CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_URL=http://schema-registry:8081",
      "CLASSPATH=/usr/share/java/monitoring-interceptors/monitoring-interceptors-${var.cp_version}.jar:/padogrid/plugins/*:/padogrid/lib/*",
      "CONNECT_PRODUCER_INTERCEPTOR_CLASSES=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor",
      "CONNECT_CONSUMER_INTERCEPTOR_CLASSES=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
      "CONNECT_PLUGIN_PATH=/usr/share/java,/usr/share/confluent-hub-components,/padogrid/plugins,/padogrid/lib",
      "CONNECT_LOG4J_LOGGERS=org.apache.zookeeper=ERROR,org.I0Itec.zkclient=ERROR,org.reflections=ERROR"]
  restart = "no"
  must_run = "true"
  network_mode= "${docker_network.debezium_cp.name}"
}

resource "docker_image" "control-center" {
  name = "confluentinc/cp-enterprise-control-center:${var.cp_version}"
  keep_locally = true
}

resource "docker_container" "control-center" {
  image = docker_image.control-center.latest
  name  = "control-center"
  hostname = "control-center"
  depends_on = [docker_container.broker, docker_container.schema-registry, docker_container.connect, docker_container.ksqldb-server]
  ports {
    internal = 9021
    external = 9021
  }
  env = [
      "CONTROL_CENTER_BOOTSTRAP_SERVERS=broker:29092",
      "CONTROL_CENTER_CONNECT_CONNECT-DEFAULT_CLUSTER=connect:8083",
      "CONTROL_CENTER_KSQL_KSQLDB1_URL=http://ksqldb-server:8088",
      "CONTROL_CENTER_KSQL_KSQLDB1_ADVERTISED_URL=http://localhost:8088",
      "CONTROL_CENTER_SCHEMA_REGISTRY_URL=http://schema-registry:8081",
      "CONTROL_CENTER_REPLICATION_FACTOR=1",
      "CONTROL_CENTER_INTERNAL_TOPICS_PARTITIONS=1",
      "CONTROL_CENTER_MONITORING_INTERCEPTOR_TOPIC_PARTITIONS=1",
      "CONFLUENT_METRICS_TOPIC_REPLICATION=1",
      "PORT: 9021"]
  restart = "no"
  must_run = "true"
  network_mode= "${docker_network.debezium_cp.name}"
}

resource "docker_image" "ksqldb-server" {
  name = "confluentinc/cp-ksqldb-server:${var.cp_version}"
  keep_locally = true
}

resource "docker_container" "ksqldb-server" {
  image = docker_image.ksqldb-server.latest
  name  = "ksqldb-server"
  hostname = "ksqldb-server"
  depends_on = [docker_container.broker, docker_container.connect]
  ports {
    internal = 8088
    external = 8088
  }
  env = [
      "KSQL_CONFIG_DIR=/etc/ksql",
      "KSQL_BOOTSTRAP_SERVERS=broker:29092",
      "KSQL_HOST_NAME=ksqldb-server",
      "KSQL_LISTENERS=http://0.0.0.0:8088",
      "KSQL_CACHE_MAX_BYTES_BUFFERING=0",
      "KSQL_KSQL_SCHEMA_REGISTRY_URL=http://schema-registry:8081",
      "KSQL_PRODUCER_INTERCEPTOR_CLASSES=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor",
      "KSQL_CONSUMER_INTERCEPTOR_CLASSES=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
      "KSQL_KSQL_CONNECT_URL=http://connect:8083",
      "KSQL_KSQL_LOGGING_PROCESSING_TOPIC_REPLICATION_FACTOR=1",
      "KSQL_KSQL_LOGGING_PROCESSING_TOPIC_AUTO_CREATE=true",
      "KSQL_KSQL_LOGGING_PROCESSING_STREAM_AUTO_CREATE=true"]
  restart = "no"
  must_run = "true"
  network_mode= "${docker_network.debezium_cp.name}"
}

resource "docker_image" "ksqldb-cli" {
  name = "confluentinc/cp-ksqldb-cli:${var.cp_version}"
  keep_locally = true
}

resource "docker_container" "ksqldb-cli" {
  image = docker_image.ksqldb-cli.latest
  name  = "ksqldb-cli"
  hostname = "ksqldb-cli"
  depends_on = [docker_container.broker, docker_container.connect, docker_container.ksqldb-server]
  entrypoint = ["/bin/sh"]
  tty=true
  restart = "no"
  must_run = "true"
  network_mode= "${docker_network.debezium_cp.name}"
}

resource "docker_image" "rest-proxy" {
  name = "confluentinc/cp-kafka-rest:${var.cp_version}"
  keep_locally = true
}

resource "docker_container" "rest-proxy" {
  image = docker_image.rest-proxy.latest
  name  = "rest-proxy"
  hostname = "rest-proxy"
  depends_on = [docker_container.broker, docker_container.schema-registry]
  ports {
    internal = 8082
    external = 8082
  }
  env = [
      "KAFKA_REST_HOST_NAME=rest-proxy",
      "KAFKA_REST_BOOTSTRAP_SERVERS=broker:29092",
      "KAFKA_REST_LISTENERS=http://0.0.0.0:8082",
      "KAFKA_REST_SCHEMA_REGISTRY_URL=http://schema-registry:8081"]
  restart = "no"
  must_run = "true"
  network_mode= "${docker_network.debezium_cp.name}"
}

#resource "docker_image" "padogrid" {
#  name         = "padogrid/padogrid:latest"
#  keep_locally = true
#}
#
#resource "docker_container" "padogrid" {
#  image = docker_image.padogrid.latest
#  name  = "padogrid"
#  ports {
#    internal = 8080
#    external = 8080
#  }
#}

