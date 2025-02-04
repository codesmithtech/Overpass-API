FROM nginx:1.21 AS builder

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install --no-install-recommends --no-install-suggests -y \
    autoconf \
    automake \
    bash \
    bzip2 \
    ca-certificates \
    curl \
    expat \
    fcgiwrap \
    g++ \
    libexpat1-dev \
    liblz4-1 \
    liblz4-dev \
    libtool \
    m4 \
    make \
    osmium-tool \
    python3 \
    python3-venv \
    supervisor \
    wget \
    zlib1g \
    zlib1g-dev

ADD http://dev.overpass-api.de/releases/osm-3s_v0.7.61.8.tar.gz /app/src.tar.gz

RUN  mkdir -p /app/src \
    && cd /app/src \
    && tar -x -z --strip-components 1 -f ../src.tar.gz \
    && autoscan \
    && aclocal \
    && autoheader \
    && libtoolize \
    && automake --add-missing  \
    && autoconf \
    && CXXFLAGS='-O2' CFLAGS='-O2' ./configure --prefix=/app --enable-lz4 \
    && make dist install clean \
    && mkdir -p /db/diffs /app/etc \
    && cp -r /app/src/rules /app/etc/rules \
    && rm -rf /app/src /app/src.tar.gz

FROM nginx:1.21

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install --no-install-recommends --no-install-suggests -y \
    bash \
    bzip2 \
    ca-certificates \
    curl \
    expat \
    fcgiwrap \
    jq \
    liblz4-1 \
    osmium-tool \
    python3 \
    python3-venv \
    supervisor \
    wget \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app /app

ADD https://raw.githubusercontent.com/geofabrik/sendfile_osm_oauth_protector/master/oauth_cookie_client.py \
    /app/bin/
RUN sed -i -e 's/allow_read_prefs": "yes"/allow_read_prefs": "1"/g' /app/bin/oauth_cookie_client.py
RUN addgroup overpass && adduser --home /db --disabled-password --gecos overpass --ingroup overpass overpass

COPY requirements.txt /app/

RUN python3 -m venv /app/venv \
    && /app/venv/bin/pip install -r /app/requirements.txt --only-binary osmium

RUN mkdir /nginx /docker-entrypoint-initdb.d && chown nginx:nginx /nginx && chown -R overpass:overpass /db

COPY etc/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY etc/nginx-overpass.conf.template /etc/nginx/nginx.conf.template

COPY bin/update_overpass.sh bin/update_overpass_loop.sh bin/rules_loop.sh bin/dispatcher_start.sh bin/start_fcgiwarp.sh /app/bin/

COPY docker-entrypoint.sh docker-healthcheck.sh /app/

RUN chmod a+rx /app/docker-entrypoint.sh /app/bin/update_overpass.sh /app/bin/rules_loop.sh /app/bin/dispatcher_start.sh \
    /app/bin/oauth_cookie_client.py /app/bin/start_fcgiwarp.sh

ENV OVERPASS_RULES_LOAD=1
ENV OVERPASS_USE_AREAS=true
ENV OVERPASS_ALLOW_DUPLICATE_QUERIES=no

EXPOSE 80

HEALTHCHECK --start-period=48h CMD /app/docker-healthcheck.sh

CMD ["/app/docker-entrypoint.sh"]
