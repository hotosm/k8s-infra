FROM python:3.12-slim-trixie AS build
RUN apt-get update --quiet \
    && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --quiet --no-install-recommends \
        "build-essential" \
        "gcc" \
        "cmake" \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-warn-script-location --break-system-packages \
      --no-cache-dir -r requirements.txt


FROM python:3.12-slim-trixie AS runtime
COPY --from=build /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=build /usr/local/bin /usr/local/bin
