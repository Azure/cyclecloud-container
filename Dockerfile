FROM openjdk:8

WORKDIR /cs-install

ENV CS_ROOT /opt/cycle_server

ADD . /cs-install

RUN /cs-install/scripts/install.sh

CMD ["/cs-install/scripts/run.sh"]
