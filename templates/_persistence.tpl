{{/*
Storage, the same way osm-seed does it. The pod always mounts a PVC:

  cloudProvider k3s
    localVolumeHostPath set   -> static hostPath PV on that folder, PVC bound to it
    localVolumeHostPath empty -> dynamic PVC on local-path (localVolumeSize)
  cloudProvider aws
    AWS_ElasticBlockStore_volumeID set   -> static PV on that EBS volume, PVC bound to it
    AWS_ElasticBlockStore_volumeID empty -> dynamic PVC (storageClassName, size)
*/}}

{{- define "restore.pv.static" -}}
{{- $p := .Values.persistenceDisk -}}
{{- if or (and (eq .Values.cloudProvider "k3s") $p.localVolumeHostPath) (and (eq .Values.cloudProvider "aws") $p.AWS_ElasticBlockStore_volumeID) }}true{{- end -}}
{{- end -}}
