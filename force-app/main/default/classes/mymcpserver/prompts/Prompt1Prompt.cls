public class Prompt1Prompt implements IMCPPrompt {

    public String getName()        { return 'prompt1'; }
    public String getTitle()       { return 'Prompt 1'; }
    public String getDescription() { return 'Prompt 1 Description'; }
    public String getServerName()  { return 'MyMCPServer'; }

    public List<Map<String, Object>> getArguments() {
        return new List<Map<String, Object>>{
            new Map<String, Object>{ 'name' => 'name', 'description' => 'the name', 'required' => true },
            new Map<String, Object>{ 'name' => 'output', 'description' => 'the output', 'required' => false }
        };
    }

    public List<Map<String, Object>> getMessages(Map<String, String> args) {
        String text = 'Prompt 1 Description';
        if (args != null) {
            for (String key : args.keySet()) {
                text += '\n' + key + ': ' + args.get(key);
            }
        }
        return new List<Map<String, Object>>{
            new Map<String, Object>{
                'role'    => 'user',
                'content' => new Map<String, Object>{ 'type' => 'text', 'text' => text }
            }
        };
    }
}
