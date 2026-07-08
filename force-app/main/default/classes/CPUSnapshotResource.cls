public class CPUSnapshotResource implements IMCPResource {
    public String getUri()         { return 'file:///pcmetrics/snapshots/cpu-load.png'; }
    public String getName()        { return 'CPU Load Snapshot'; }
    public String getTitle()       { return 'CPU Load Chart'; }
    public String getDescription() { return 'PNG chart snapshot of CPU core load at the time of capture.'; }
    public String getMimeType()    { return 'image/png'; }
    public String getText()        { return null; }
    // Minimal valid 1x1 red PNG (base64-encoded)
    public String getBlob()        { return 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg=='; }
    public String getServerName()  { return 'PCMetrics'; }
}
