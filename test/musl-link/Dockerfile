# Checks that a rust-musl image compiles and links aws-lc-sys and
# aws-lc-fips-sys for both musl targets, the way consumers build them.
#
# C compiled against the host glibc headers instead of musl's emits __isoc23_*
# symbols that musl lacks (v52); musl headers alone hide the kernel headers
# aws-lc-fips-sys needs, e.g. linux/random.h (v53). Both targets are built on
# whichever arch runs this, since consumers cross-compile.
ARG RUST_MUSL_IMAGE=ghcr.io/linkerd/dev:ci-rust-musl
FROM ${RUST_MUSL_IMAGE}
# aws-lc-fips-sys runs Go while building its FIPS module; consumers install it
# the same way.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends golang && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /musl-link
COPY . .
RUN cargo fetch --locked
# just-cargo sets the musl CC, AR and linker as consumers' builds do. The C
# archives are checked as well as the binary, since the linker only reports
# __isoc23_* symbols from objects it pulls in.
# Every target runs even if one fails, so a failure shows all affected targets.
RUN failed='' ; \
    for target in x86_64-unknown-linux-musl aarch64-unknown-linux-musl ; do \
        echo "== $target" ; \
        ( \
            just-cargo profile=release target="$target" build --locked || exit 1 ; \
            bin="target/$target/release/musl-link" ; \
            file "$bin" ; \
            archives=$(find "target/$target/release/build" -name 'libaws_lc*.a') ; \
            [ -n "$archives" ] || { echo "no aws-lc archives found" >&2 ; exit 1 ; } ; \
            for f in "$bin" $archives ; do \
                n=$(nm -A "$f" | grep -c __isoc23_ || true) ; \
                echo "nm __isoc23_ $n $f" ; \
                [ "$n" = 0 ] || exit 1 ; \
            done \
        ) || failed="$failed $target" ; \
    done ; \
    [ -z "$failed" ] || { echo "failed:$failed" >&2 ; exit 1 ; }
