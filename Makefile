# Usage:
# 
#  make            build image on local machine (requires GNU wget, cpio, dd, gpg, gzip, sed, md5sum and xorriso)
#  make in-docker  build image in Docker
#  make clean      cleanup working directory (should be called before re-building image to keep initrd sane)
#  make clean-all  remove everything including .iso files
# 
# Variables:
# 
#  DEBIAN_VERSION  desired Debian netinst version to download from https://cdimage.debian.org/debian-cd/
#  IMAGE_NAME      result ISO image filename suffix
#  PRESEED         preseed configuration filename



DEBIAN_VERSION ?= 12.4.0
IMAGE_NAME ?= preseed
PRESEED ?= preseed.cfg

.PHONY: clean check-reqs
.DELETE_ON_ERROR: SHA512SUMS SHA512SUMS.sign debian-$(DEBIAN_VERSION)-amd64-netinst.iso isofiles isohdpfx.bin
.INTERMEDIATE: isohdpfx.bin

debian-$(DEBIAN_VERSION)-amd64-netinst_$(IMAGE_NAME).iso: isofiles/install.amd/initrd.gz isohdpfx.bin
	@chmod -v +w isofiles/isolinux isofiles/isolinux/isolinux.cfg isofiles/boot/grub isofiles/boot/grub/grub.cfg isofiles/md5sum.txt isofiles/.disk/mkisofs

	sed -e 's/timeout 0/timeout 3/g' -e '$$adefault auto' -i isofiles/isolinux/isolinux.cfg
	sed -e '/play 960 440 1 0 4 440 1/a set default="2>5"\nset timeout=3' -i isofiles/boot/grub/grub.cfg

	cd isofiles && find -follow -type f ! -name md5sum.txt -print0 2>/dev/null | xargs -0 md5sum >md5sum.txt
	@chmod -v 444 isofiles/md5sum.txt

	$(eval VOLID := $(shell dd if="debian-$(DEBIAN_VERSION)-amd64-netinst.iso" bs=32 count=1 skip=32808 iflag=skip_bytes status=none | xargs))
	$(eval MKISOFS := xorriso -as mkisofs -r -checksum_algorithm_iso sha256,sha512 -V "$(VOLID)" \
		-o "debian-$(DEBIAN_VERSION)-amd64-netinst_$(IMAGE_NAME).iso" -J -joliet-long -isohybrid-mbr "./isohdpfx.bin" \
		-b "isolinux/isolinux.bin" -c "isolinux/boot.cat" -boot-load-size 4 -boot-info-table -no-emul-boot \
		-eltorito-alt-boot -e "boot/grub/efi.img" -no-emul-boot -isohybrid-gpt-basdat -isohybrid-apm-hfsplus "./isofiles")

	echo $(MKISOFS) >isofiles/.disk/mkisofs
	@chmod -v -w isofiles/isolinux isofiles/isolinux/isolinux.cfg isofiles/boot/grub isofiles/boot/grub/grub.cfg isofiles/.disk/mkisofs

	$(MKISOFS)

isofiles/install.amd/initrd.gz: isofiles/install.amd/initrd $(PRESEED)
	echo $(PRESEED) | cpio -H newc -o -A -F isofiles/install.amd/initrd
	@gzip -v isofiles/install.amd/initrd
	@chmod -v -w isofiles/install.amd isofiles/install.amd/initrd.gz

$(PRESEED):
	@test -f $(PRESEED)

isohdpfx.bin: debian-$(DEBIAN_VERSION)-amd64-netinst.iso
	dd if="debian-$(DEBIAN_VERSION)-amd64-netinst.iso" bs=1 count=432 of=isohdpfx.bin

isofiles/install.amd/initrd: isofiles
	@chmod -v +w isofiles/install.amd isofiles/install.amd/initrd.gz
	@gunzip -v isofiles/install.amd/initrd.gz

isofiles: debian-$(DEBIAN_VERSION)-amd64-netinst.iso SHA512SUMS SHA512SUMS.sign
	@gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 988021A964E6EA7D DA87E80D6294BE9B 42468F4009EA8AC3
	@gpg --no-options --verify SHA512SUMS.sign SHA512SUMS
	@grep "debian-$(DEBIAN_VERSION)-amd64-netinst.iso" SHA512SUMS | sha512sum -c

	@mkdir -pv isofiles
	xorriso -osirrox on -indev "debian-$(DEBIAN_VERSION)-amd64-netinst.iso" -extract / isofiles

debian-$(DEBIAN_VERSION)-amd64-netinst.iso: check-reqs
	@wget --no-verbose --show-progress --progress=bar:force:noscroll \
		"https://cdimage.debian.org/debian-cd/$(DEBIAN_VERSION)/amd64/iso-cd/debian-$(DEBIAN_VERSION)-amd64-netinst.iso" \
		-O "debian-$(DEBIAN_VERSION)-amd64-netinst.iso" \

SHA512SUMS:
	@wget --no-verbose --show-progress --progress=bar:force:noscroll -O SHA512SUMS \
		"https://cdimage.debian.org/debian-cd/$(DEBIAN_VERSION)/amd64/iso-cd/SHA512SUMS"

SHA512SUMS.sign:
	@wget --no-verbose --show-progress --progress=bar:force:noscroll -O SHA512SUMS.sign \
		"https://cdimage.debian.org/debian-cd/$(DEBIAN_VERSION)/amd64/iso-cd/SHA512SUMS.sign"

check-reqs:
	$(if $(shell wget --version | grep GNU),,$(error GNU wget is not installed))
	$(foreach bin,cpio dd gpg gzip sed md5sum xorriso wget,$(if $(shell which $(bin)),,$(error $(bin) is not available in PATH)))

clean:
	test -d isofiles && chmod +w -R isofiles || true
	rm -rf isofiles isohdpfx.bin

clean-all: clean
	rm -f SHA512SUMS SHA512SUMS.sign debian-$(DEBIAN_VERSION)-amd64-netinst.iso debian-$(DEBIAN_VERSION)-amd64-netinst_$(IMAGE_NAME).iso

in-docker:
	DOCKER_CLI_HINTS=false docker build . \
		--build-arg DEBIAN_VERSION=$(DEBIAN_VERSION) \
		--build-arg IMAGE_NAME=$(IMAGE_NAME) \
		--build-arg PRESEED=$(PRESEED) \
		--tag debian-netinst:$(DEBIAN_VERSION)-$(IMAGE_NAME)

	docker run --detach --name tmp-debian-netinst debian-netinst:$(DEBIAN_VERSION)-$(IMAGE_NAME)
	docker cp tmp-debian-netinst:/debian/debian-$(DEBIAN_VERSION)-amd64-netinst_$(IMAGE_NAME).iso .
	docker container rm tmp-debian-netinst
	docker image rm debian-netinst:$(DEBIAN_VERSION)-$(IMAGE_NAME)
