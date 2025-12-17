FROM otel/opentelemetry-collector-contrib:0.114.0

# Copy the collector configuration
COPY collector-config.yaml /etc/otelcol-contrib/config.yaml

# Expose OTLP HTTP receiver port
EXPOSE 4318

# Expose health check port
EXPOSE 13133

# Run the collector with the custom configuration
CMD ["--config=/etc/otelcol-contrib/config.yaml"]


