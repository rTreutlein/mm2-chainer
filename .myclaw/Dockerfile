FROM swipl:9.3.33

ENV RUSTUP_HOME=/usr/local/rustup

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        pkg-config \
        python3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | CARGO_HOME=/usr/local/cargo sh -s -- \
            -y --profile minimal --default-toolchain nightly-2026-02-23 --no-modify-path \
    && chmod -R a+rX /usr/local/cargo /usr/local/rustup \
    && ln -s /usr/local/cargo/bin/cargo /usr/local/bin/cargo \
    && ln -s /usr/local/cargo/bin/rustc /usr/local/bin/rustc \
    && install -d -m 1777 /cache/cargo /cache/target /cache/petta-ffi
