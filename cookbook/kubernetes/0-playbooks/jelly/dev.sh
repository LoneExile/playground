for dev in dri dma_heap mali0 rga mpp_service \
    iep mpp-service vpu_service vpu-service \
    hevc_service hevc-service rkvdec rkvenc vepu h265e ; do \
   [ -e "/dev/$dev" ] && echo " --device /dev/$dev"; \
  done
