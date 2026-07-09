public class Resource1Resource implements IMCPResource {
    public String getUri()         { return 'file:///myfile1.json'; }
    public String getName()        { return 'Resource 1'; }
    public String getTitle()       { return 'Resource 1'; }
    public String getDescription() { return 'Resource 1 Description'; }
    public String getMimeType()    { return 'application/json'; }
    public String getText()        { return '{ "name": "the_name" }'; }
    public String getBlob()        { return null; }
    public String getServerName()  { return 'MyMCPServer'; }
}
