# Base 이미지 설정
FROM node:lts AS base
ARG TARGETOS
ARG TARGETARCH
WORKDIR /focalboard
RUN git clone https://github.com/AskFront/focalboard-af.git .

# Node.js 빌드 단계
FROM base AS nodebuild
WORKDIR /focalboard/webapp
RUN apt-get update \ 
    && apt-get install -y --no-install-recommends \
    libtool automake autoconf pkg-config nasm build-essential
RUN CPPFLAGS="-DPNG_ARM_NEON_OPT=0" npm install --no-optional && \
    npm run pack

# Go 빌드 단계
FROM golang:bookworm AS gobuild
ARG TARGETOS
ARG TARGETARCH
COPY --from=base /focalboard /go/src/focalboard
WORKDIR /go/src/focalboard/server/server

## Depress 'x-amz-checksum-algorithm' force
RUN go install && \
    cd /go/pkg/mod/github.com/mattermost/mattermost/server/v8@v8.0.0-20240529104128-9d30a62c9471/platform/shared/filestore && \
    sed -i '/options.PartSize = uint64(uploadPartSize)/a \        options.SendContentMd5 = true' s3store.go

WORKDIR /go/src/focalboard
RUN EXCLUDE_PLUGIN=true EXCLUDE_SERVER=true EXCLUDE_ENTERPRISE=true make server-docker os=${TARGETOS} arch=${TARGETARCH}

# 최적화 및 단축 단계
FROM navystack/ngx_mod:1.26.0 AS layershorter
RUN mkdir -p /opt/focalboard/data/files && \
    chown -R nobody:nogroup /opt/focalboard
COPY --from=nodebuild --chown=nobody:nogroup /focalboard/webapp/pack /opt/focalboard/pack/
COPY --from=gobuild --chown=nobody:nogroup /go/src/focalboard/bin/docker/focalboard-server /opt/focalboard/bin/
COPY --from=gobuild --chown=nobody:nogroup /go/src/focalboard/LICENSE.txt /opt/focalboard/LICENSE.txt

RUN apt-get update && \
    apt-get install -y --no-install-recommends tini && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 최종 이미지 설정
FROM nginx:1.31.5 AS final
WORKDIR /opt/focalboard
COPY --from=layershorter /usr/bin/tini /usr/bin/tini
COPY --from=layershorter --chown=nobody:nogroup /opt/focalboard/ /opt/focalboard
COPY --from=layershorter /usr/lib/nginx/modules/*.so /usr/lib/nginx/modules/
COPY --from=layershorter /etc/nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

EXPOSE 80/tcp 9092/tcp
VOLUME /opt/focalboard/data
COPY scripts/focalboard-nginx.sh /

ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]
CMD ["/focalboard-nginx.sh"]
