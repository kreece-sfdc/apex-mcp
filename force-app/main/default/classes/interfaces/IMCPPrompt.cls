public interface IMCPPrompt {
    String getName();
    String getTitle();
    String getDescription();
    List<Map<String, Object>> getArguments();
    String getServerName();
    List<Map<String, Object>> getMessages(Map<String, String> args);
}
