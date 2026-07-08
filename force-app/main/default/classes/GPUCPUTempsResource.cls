public class GPUCPUTempsResource implements IMCPResource {
    public String getUri()         { return 'file:///pcmetrics/logs/temperatures.json'; }
    public String getName()        { return 'GPU & CPU Temps'; }
    public String getTitle()       { return 'Live Hardware Metrics'; }
    public String getDescription() { return 'Real-time temperature and load logs for the graphics card and processor.'; }
    public String getMimeType()    { return 'application/json'; }
    public String getText()        { return '{"timestamp":"2026-07-07T21:00:00Z","cpu":{"model":"AMD Ryzen 9 7950X","temperature_c":68,"load_percent":42},"gpu":{"model":"NVIDIA RTX 4090","temperature_c":74,"load_percent":87,"vram_used_mb":18432,"vram_total_mb":24576}}'; }
    public String getBlob()        { return null; }
    public String getServerName()  { return 'PCMetrics'; }
}
