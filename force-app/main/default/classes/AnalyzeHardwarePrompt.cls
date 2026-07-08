public class AnalyzeHardwarePrompt implements IMCPPrompt {

    public String getName()        { return 'analyze_hardware'; }
    public String getTitle()       { return 'Analyze Hardware Performance'; }
    public String getDescription() { return 'Generate an analysis prompt for current PC hardware metrics'; }
    public String getServerName()  { return 'PCMetrics'; }

    public List<Map<String, Object>> getArguments() {
        return new List<Map<String, Object>>{
            new Map<String, Object>{
                'name'        => 'focus',
                'description' => 'Component to focus on: cpu, gpu, or all',
                'required'    => false
            }
        };
    }

    public List<Map<String, Object>> getMessages(Map<String, String> args) {
        GPUCPUTempsResource res = new GPUCPUTempsResource();
        String metrics = res.getText();

        String focus = args != null ? args.get('focus') : null;
        String instruction;
        if (focus == 'cpu') {
            instruction = 'Focus your analysis on CPU performance only.';
        } else if (focus == 'gpu') {
            instruction = 'Focus your analysis on GPU performance only.';
        } else {
            instruction = 'Analyze both CPU and GPU performance.';
        }

        String text = 'Analyze the following PC hardware metrics. ' + instruction
            + '\n\nMetrics:\n' + metrics;

        return new List<Map<String, Object>>{
            new Map<String, Object>{
                'role'    => 'user',
                'content' => new Map<String, Object>{
                    'type' => 'text',
                    'text' => text
                }
            }
        };
    }
}
