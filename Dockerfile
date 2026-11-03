# TokenBar server: REST API + Flutter Web UI in one small image.
#
#   docker build -t tokenbar .
#   docker run -d -p 8787:8787 -v tokenbar-data:/data -e TOKENBAR_TOKEN=change-me tokenbar

ARG FLUTTER_VERSION=3.47.9

FROM ghcr.io/cirruslabs/flutter:${FLUTTER_VERSION} AS build
WORKDIR /src
COPY pubspec.yaml pubspec.lock* ./
COPY packages/tokenbar_core/pubspec.yaml packages/tokenbar_core/
COPY packages/tokenbar_server/pubspec.yaml packages/tokenbar_server/
RUN flutter pub get
COPY . .
RUN flutter build web --release --no-wasm-dry-run \
 && cd packages/tokenbar_server && dart build cli -o /out

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home /data tokenbar \
 && mkdir -p /data && chown tokenbar /data
COPY --from=build /out/bundle /app/tokenbar
COPY --from=build /src/build/web /app/web
RUN ln -s /app/tokenbar/bin/tokenbar /usr/local/bin/tokenbar
ENV TOKENBAR_DATA=/data TOKENBAR_WEB=/app/web PORT=8787
USER tokenbar
VOLUME /data
EXPOSE 8787
ENTRYPOINT ["tokenbar"]
CMD ["serve"]
