public class MyMCPServerServer implements IMCPServer {
    public String getUri()         { return 'mymcpserver/mcp'; }
    public String getName()        { return 'MyMCPServer'; }
    public String getTitle()       { return 'My MCP Server'; }
    public String getDescription() { return 'Accesses really cool resources, tools, and prompts to do cool stuff with'; }
    public String getMimeType()    { return 'application/json'; }
}
