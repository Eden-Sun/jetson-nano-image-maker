FROM ubuntu:latest

RUN apt update
RUN apt install -y libxml2-utils lbzip2 python3 bzip2 wget
WORKDIR /tmp

RUN wget https://developer.nvidia.com/downloads/embedded/l4t/r32_release_v7.4/t210/jetson-210_linux_r32.7.4_aarch64.tbz2
RUN tar -xvf jetson-210_linux_r32.7.4_aarch64.tbz2
RUN mkdir rootfs

WORKDIR /tmp/Linux_for_Tegra/
COPY build.sh /tmp/Linux_for_Tegra/

CMD ["bash", "build.sh"]
