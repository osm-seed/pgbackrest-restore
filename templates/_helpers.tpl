{{- define "restore.name" -}}{{ .Release.Name }}-pgbackrest-restore{{- end -}}
{{- define "restore.labels" -}}
app.kubernetes.io/name: pgbackrest-restore
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "restore.secret" -}}{{ .Values.source.existingSecret | default (include "restore.name" .) }}{{- end -}}
