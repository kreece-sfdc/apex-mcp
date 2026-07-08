public class PCMetricsServer implements IMCPServer {
    public String getUri()         { return 'pcmetrics/mcp'; }
    public String getName()        { return 'PCMetrics'; }
    public String getTitle()       { return 'PC Hardware Metrics Server'; }
    public String getDescription() { return 'Exposes live CPU, GPU, and memory metrics from a local PC.'; }
    public String getMimeType()    { return 'application/json'; }
}
