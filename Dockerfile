ARG DEBIAN_VERSION="12.4.0"
ARG IMAGE_NAME="preseed"
ARG PRESEED="preseed.cfg"



FROM alpine:latest as xorriso-builder

WORKDIR /usr/local/src/xorriso

RUN apk --no-cache add file g++ git linux-headers make texinfo zlib-dev

RUN git clone --depth=1 "https://github.com/Distrotech/xorriso.git" .

RUN ./configure CFLAGS="$CFLAGS -DLibburn_udev_wait_useC=0" \
 \
 && make \
 && make check \
 \
 && mkdir stage \
 && make install DESTDIR=$(realpath stage)



FROM alpine:latest as debian-netinst-preseed

ARG DEBIAN_VERSION
ARG IMAGE_NAME
ARG PRESEED

ENV PATH=/usr/local/bin:${PATH}

WORKDIR /debian

RUN apk --no-cache add cpio gnupg gzip sed wget

RUN gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 988021A964E6EA7D DA87E80D6294BE9B 42468F4009EA8AC3

RUN wget --no-verbose --show-progress --progress=bar:force:noscroll \
        "https://cdimage.debian.org/debian-cd/${DEBIAN_VERSION}/amd64/iso-cd/debian-${DEBIAN_VERSION}-amd64-netinst.iso" \
        -O "debian-${DEBIAN_VERSION}-amd64-netinst.iso" \
 \
 && wget --no-verbose --show-progress --progress=bar:force:noscroll -O SHA512SUMS \
        "https://cdimage.debian.org/debian-cd/${DEBIAN_VERSION}/amd64/iso-cd/SHA512SUMS" \
 \
 && wget --no-verbose --show-progress --progress=bar:force:noscroll -O SHA512SUMS.sign \
        "https://cdimage.debian.org/debian-cd/${DEBIAN_VERSION}/amd64/iso-cd/SHA512SUMS.sign" \
 \
 && gpg --no-options --verify SHA512SUMS.sign SHA512SUMS \
 && grep "debian-${DEBIAN_VERSION}-amd64-netinst.iso" SHA512SUMS | sha512sum -c

COPY --from=xorriso-builder /usr/local/src/xorriso/stage/usr/local/bin/. /usr/local/bin/

RUN mkdir -v isofiles \
 && xorriso -osirrox on -indev "debian-${DEBIAN_VERSION}-amd64-netinst.iso" -extract / isofiles \
 \
 && chmod -v +w isofiles/install.amd isofiles/install.amd/initrd.gz \
 && gunzip -v isofiles/install.amd/initrd.gz \
 \
 && dd if="debian-${DEBIAN_VERSION}-amd64-netinst.iso" bs=1 count=432 of=isohdpfx.bin \
 && dd if="debian-${DEBIAN_VERSION}-amd64-netinst.iso" bs=32 count=1 skip=32808 iflag=skip_bytes status=none >volid

COPY "${PRESEED}" .

RUN echo "${PRESEED}" | cpio -H newc -o -A -F isofiles/install.amd/initrd \
 && gzip -v isofiles/install.amd/initrd \
 && chmod -v -w isofiles/install.amd isofiles/install.amd/initrd.gz \
 \
 && chmod -v +w isofiles/isolinux isofiles/isolinux/isolinux.cfg isofiles/boot/grub \
        isofiles/boot/grub/grub.cfg isofiles/md5sum.txt isofiles/.disk/mkisofs \
 \
 && sed -e 's/timeout 0/timeout 3/g' -e '$adefault auto' -i isofiles/isolinux/isolinux.cfg \
 && sed -e '/play 960 440 1 0 4 440 1/a set default="2>5"\nset timeout=3' -i isofiles/boot/grub/grub.cfg \
 \
 && echo "Recalculating MD5 sums..." \
 && cd isofiles && find -follow -type f ! -name md5sum.txt -print0 2>/dev/null | xargs -0 md5sum >md5sum.txt && cd .. \
 && chmod -v 444 isofiles/md5sum.txt \
 \
 && VOLID=$(cat volid) \
 && MKISOFS="xorriso -as mkisofs -r -checksum_algorithm_iso sha256,sha512 -V \"${VOLID}\" \
                -o \"debian-${DEBIAN_VERSION}-amd64-netinst_${IMAGE_NAME}.iso\" -J -joliet-long \
                -isohybrid-mbr ./isohdpfx.bin -b isolinux/isolinux.bin -c isolinux/boot.cat \
                -boot-load-size 4 -boot-info-table -no-emul-boot -eltorito-alt-boot -e boot/grub/efi.img \
                -no-emul-boot -isohybrid-gpt-basdat -isohybrid-apm-hfsplus ./isofiles" \
 \
 && MKISOFS=$(echo "${MKISOFS}" | tr -s ' ') \
 && echo "${MKISOFS}" >isofiles/.disk/mkisofs \
 \
 && chmod -v -w isofiles/isolinux isofiles/isolinux/isolinux.cfg isofiles/boot/grub \
        isofiles/boot/grub/grub.cfg isofiles/.disk/mkisofs \
 \
 && eval "${MKISOFS}"
