# Build stage
FROM registry.access.redhat.com/ubi8/ubi-minimal as build

ARG JAVA_PACKAGE=java-11-openjdk-headless
ARG MAVEN_VERSION=3.8.8

ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en'

# Install java and maven
RUN microdnf install curl ca-certificates tar gzip ${JAVA_PACKAGE} \
    && microdnf update \
    && microdnf clean all \
    && curl -L https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz | tar xz \
    && mv apache-maven-${MAVEN_VERSION} /opt/maven \
    && ln -s /opt/maven/bin/mvn /usr/local/bin/mvn \
    && JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java)))) \
    && echo "export JAVA_HOME=$JAVA_HOME" >> /etc/profile.d/java.sh \
    && echo "export PATH=$JAVA_HOME/bin:$PATH" >> /etc/profile.d/java.sh \
    && chmod +x /etc/profile.d/java.sh \
    && echo "JAVA_HOME set to: $JAVA_HOME"

# Copy the Maven project
COPY . /build/
WORKDIR /build

# Build the application
RUN . /etc/profile.d/java.sh && java -version && mvn clean package -DskipTests

# Run stage
FROM registry.access.redhat.com/ubi8/ubi-minimal

ARG JAVA_PACKAGE=java-11-openjdk-headless
ARG RUN_JAVA_VERSION=1.3.8

ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en'

# Install java and the run-java script
RUN microdnf install curl ca-certificates ${JAVA_PACKAGE} \
    && microdnf update \
    && microdnf clean all \
    && JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java)))) \
    && echo "export JAVA_HOME=$JAVA_HOME" >> /etc/profile.d/java.sh \
    && echo "export PATH=$JAVA_HOME/bin:$PATH" >> /etc/profile.d/java.sh \
    && chmod +x /etc/profile.d/java.sh \
    && mkdir /deployments \
    && chown 1001 /deployments \
    && chmod "g+rwX" /deployments \
    && chown 1001:root /deployments \
    && curl https://repo1.maven.org/maven2/io/fabric8/run-java-sh/${RUN_JAVA_VERSION}/run-java-sh-${RUN_JAVA_VERSION}-sh.sh -o /deployments/run-java.sh \
    && chown 1001 /deployments/run-java.sh \
    && chmod 540 /deployments/run-java.sh \
    && echo "securerandom.source=file:/dev/urandom" >> /etc/alternatives/jre/lib/security/java.security

# Configure the JAVA_OPTIONS
ENV JAVA_OPTIONS="-Dquarkus.http.host=0.0.0.0 -Djava.util.logging.manager=org.jboss.logmanager.LogManager"

# Copy the built application from the build stage
COPY --from=build --chown=1001 /build/target/quarkus-app/lib/ /deployments/lib/
COPY --from=build --chown=1001 /build/target/quarkus-app/*.jar /deployments/
COPY --from=build --chown=1001 /build/target/quarkus-app/app/ /deployments/app/
COPY --from=build --chown=1001 /build/target/quarkus-app/quarkus/ /deployments/quarkus/

EXPOSE 8080

# run with user 1001
USER 1001

ENTRYPOINT [ "/deployments/run-java.sh" ] 