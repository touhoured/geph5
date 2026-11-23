FROM alpine:3.23 AS base
RUN apk add --no-cache ca-certificates iproute2
ARG TARGETARCH
COPY ${TARGETARCH}/ /usr/local/bin/

FROM base AS geph5-client
ENTRYPOINT ["/usr/local/bin/geph5-client"]

FROM base AS geph5-app
ENTRYPOINT ["/usr/local/bin/geph5"]
