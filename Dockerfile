FROM phusion/baseimage:noble-1.0.2
#FROM phusion/baseimage:master

#Basic Container
RUN echo "---- INSTALL RUNTIME PACKAGES ----" && \
    apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    git \
    #ffmpeg \
    dnsutils \
    iputils-ping \
    wget \
    crudini && rm -rf /var/lib/apt/lists/*

#Build layer
RUN echo "---- INSTALL ALL BUILD-DEPENDENCIES ----" && \
    buildDeps='gcc \
    g++ \
    make \
    autoconf \
    automake \
    build-essential \
    cmake \
    git-core \
    libass-dev \
    libfreetype6-dev \
    libgnutls28-dev \
    libmp3lame-dev \
    libsdl2-dev \
    libtool \
    libva-dev \
    libvdpau-dev \
    libvorbis-dev \
    libxcb1-dev \
    libxcb-shm0-dev \
    libxcb-xfixes0-dev \
    meson \
    ninja-build \
    pkg-config \
    texinfo \
    yasm \
    libfdk-aac-dev \
    zlib1g-dev' && \
    set -x && \
    apt-get update && apt-get install -y $buildDeps --no-install-recommends && \
    rm -rf /var/lib/apt/lists/* && \
echo "---- BUILD & INSTALL MP4V2 ----" && \
    mkdir -p /tmp && \
    cd /tmp && \
    git clone https://github.com/sandreas/mp4v2 && \
    cd mp4v2 && \
    ./configure && \
    make && \
    make install && \
    make distclean && \
echo "---- BUILD & INSTALL ffmpeg ----" && \
    mkdir -p ~/ffmpeg_sources ~/bin && \
    cd ~/ffmpeg_sources && \
    git -C fdk-aac pull 2> /dev/null || git clone --depth 1 https://github.com/mstorsjo/fdk-aac && \
    cd fdk-aac && \
    autoreconf -fiv && \
    ./configure --prefix="$HOME/ffmpeg_build" --disable-shared && \
    make && \
    make install && \
    make distclean && \
    cd ~/ffmpeg_sources && \
    wget -O ffmpeg-snapshot.tar.bz2 https://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2 && \
    tar xjvf ffmpeg-snapshot.tar.bz2 && \
    cd ffmpeg && \
    PATH="$HOME/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
      --prefix="$HOME/ffmpeg_build" \
      --pkg-config-flags="--static" \
      --extra-cflags="-I$HOME/ffmpeg_build/include" \
      --extra-ldflags="-L$HOME/ffmpeg_build/lib" \
      --extra-libs="-lpthread -lm" \
      --ld="g++" \
      --bindir="$HOME/bin" \
      --enable-libfdk-aac \
      --enable-nonfree && \
    PATH="$HOME/bin:$PATH" make && \
    make install && \
    hash -r && \
    make distclean && \
    mv ~/bin/* /bin/ && \
echo "---- REMOVE ALL BUILD-DEPENDENCIES ----" && \
    apt-get purge -y --auto-remove $buildDeps && \
    ldconfig && \
    rm -r /tmp/* ~/ffmpeg_sources ~/bin

#ENV WORKDIR /mnt/
#ENV M4BTOOL_TMP_DIR /tmp/m4b-tool/
LABEL Description="Container to run m4b-tool as a deamon."

RUN echo "---- INSTALL M4B-TOOL DEPENDENCIES ----" && \
    apt-get update && apt-get install -y --no-install-recommends \
    fdkaac \
    php-cli \
    php-intl \
    php-json \
    php-mbstring \
    php-xml \
    php-curl \
    php-zip \
    libxcb-shm0-dev \
    libxcb-xfixes0-dev \
    libasound-dev \
    libsdl2-dev \
    libva-dev \
    libvdpau-dev

#Mount volumes
VOLUME /temp
VOLUME /config

ENV PUID=""
ENV PGID=""
ENV CPU_CORES=""
ENV SLEEPTIME=""

#Merge-Script importieren
ADD runscript.sh /etc/service/bot/run
ADD auto-m4b-tool.sh /

RUN echo "---- INSTALL M4B-TOOL ----" \
    && wget https://github.com/sandreas/m4b-tool/releases/download/v0.5.2/m4b-tool.phar -O /usr/local/bin/m4b-tool \
    && chmod +x /usr/local/bin/m4b-tool

#use the remommended clean command
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

