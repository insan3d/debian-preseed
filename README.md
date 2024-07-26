# Debian netinst preseed

Yet another Debian preseed configuration template.

```plain
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
```
