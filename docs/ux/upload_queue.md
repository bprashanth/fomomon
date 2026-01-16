# Upload queue

```
User opens UploadQueueScreen
  |
loadAllSessions() - filter(!isUploaded) - sort(newest first)
  |
Display gallery items
  |
User taps item - Show SessionDetailDialog
  |
User taps Delete - deleteSession() - Delete JSON + images - Refresh gallery
```

Managing state
Deleting a sessions should reflect 
1. in upload dial widget (count 0/n -> 0/n-1)
2. in gallery (when detail dialog is closed)
