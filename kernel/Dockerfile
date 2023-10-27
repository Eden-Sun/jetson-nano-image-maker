FROM ubuntu:18.04

# xxd is for video
RUN apt update && apt install -y build-essential bc libncurses5 libncurses5-dev wget xxd

ENV SMALL_VERSION=4
ENV SOURCE_NAME=public_sources_$SMALL_VERSION
WORKDIR /tmp
RUN wget -O $SOURCE_NAME https://developer.nvidia.com/downloads/embedded/l4t/r32_release_v7.${SMALL_VERSION}/sources/t210/public_sources.tbz2
RUN tar -xvf $SOURCE_NAME
RUN tar -xvf Linux_for_Tegra/source/public/kernel_src.tbz2 -C Linux_for_Tegra/source/public
WORKDIR /tmp/Linux_for_Tegra/source/public/kernel/kernel-4.9

ENV TEGRA_KERNEL_OUT=/output
RUN mkdir -p $TEGRA_KERNEL_OUT
RUN make O=$TEGRA_KERNEL_OUT tegra_defconfig
RUN make O=$TEGRA_KERNEL_OUT -j$(nproc)

# WORKDIR /tmp/Linux_for_Tegra/

# CMD ["bash", "build.sh"]
