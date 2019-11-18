FROM rocker/r-ver:3.6.1

ENV PLUMBER_PORT=5555

# install plumber
RUN R -e "install.packages(c('plumber','remotes'))"

# install other required packages, like stars and lubridate
RUN apt-get update && apt-get install libudunits2-dev libgdal-dev -y && \
  R -e "install.packages(c('sf','lubridate','stars'),repos='https://cran.rstudio.com/')"

WORKDIR /opt/openeo-r-udf
COPY /*.R ./

# open port 5555 to traffic
EXPOSE ${PLUMBER_PORT}

# when the container starts, start the main.R script
ENTRYPOINT ["Rscript", "server_start.R"]