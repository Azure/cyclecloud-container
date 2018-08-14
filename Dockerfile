FROM openjdk:8

WORKDIR /cs-install

ENV CS_ROOT /opt/cycle_server
ENV BACKUPS_DIRECTORY /azurecyclecloud

ADD . /cs-install

RUN /cs-install/scripts/install.sh

CMD ["/cs-install/scripts/run.sh"]
