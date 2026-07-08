public interface IMCPTool {
    String getName();
    String getTitle();
    String getDescription();
    Map<String, Object> getInputSchema();
    String getServerName();
    Map<String, Object> call(Map<String, Object> arguments);
}
