ARG NGINX_VERSION=1.25.3
ARG NODE_VERSION=18-bookworm
ARG GO_VERSION=1.27.1-bookworm
ARG FINAL_VERSION=bookworm-slim
ARG TARGETOS
ARG TARGETARCH
FROM navystack/focalboard:nodebuild-cache as nodebuild
FROM golang:${GO_VERSION} AS gobuild

WORKDIR /go/src/focalboard
COPY --from=nodebuild /focalboard/ /go/src/focalboard

RUN EXCLUDE_PLUGIN=true EXCLUDE_SERVER=true EXCLUDE_ENTERPRISE=true make server-docker os=${TARGETOS} arch=${TARGETARCH}