public class MatchHistoryResource implements IMCPResource {
    public String getUri()         { return 'file:///pcmetrics/current/match-history.md'; }
    public String getName()        { return 'Match History'; }
    public String getTitle()       { return 'Recent Valorant Matches'; }
    public String getDescription() { return 'Markdown file tracking wins, losses, and performance from today\'s gaming session.'; }
    public String getMimeType()    { return 'text/markdown'; }
    public String getText()        { return '# Match History\n\n| Match | Result | KDA |\n|---|---|---|\n| Ascent | Win | 22/8/6 |\n| Haven | Loss | 14/15/9 |\n| Bind | Win | 18/10/11 |'; }
    public String getBlob()        { return null; }
    public String getServerName()  { return 'PCMetrics'; }
}
