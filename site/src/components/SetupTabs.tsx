import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { CopyButton } from '@/components/CopyButton';

const URL = 'https://prompt-improver.oweninnes.com/mcp';

const CLAUDE_CODE = `claude mcp add --transport http prompt-improver ${URL}`;
const JSON_CONFIG = JSON.stringify({ mcpServers: { 'prompt-improver': { type: 'http', url: URL } } }, null, 2);

function Snippet({ code }: { code: string }) {
  return (
    <div className="space-y-2">
      <pre className="overflow-x-auto whitespace-pre-wrap break-all rounded-md border bg-muted p-3 font-mono text-xs leading-relaxed sm:text-sm">
        <code>{code}</code>
      </pre>
      <CopyButton value={code} />
    </div>
  );
}

function Steps({ items }: { items: string[] }) {
  return (
    <ol className="list-decimal space-y-1 pl-5 text-sm text-muted-foreground">
      {items.map((item) => (
        <li key={item}>{item}</li>
      ))}
    </ol>
  );
}

export function SetupTabs() {
  return (
    <Tabs defaultValue="claude-code" className="w-full">
      <TabsList className="w-full">
        <TabsTrigger value="claude-code">Claude Code</TabsTrigger>
        <TabsTrigger value="chat">Chat apps</TabsTrigger>
        <TabsTrigger value="json">JSON config</TabsTrigger>
      </TabsList>
      <TabsContent value="claude-code" className="pt-3">
        <Snippet code={CLAUDE_CODE} />
      </TabsContent>
      <TabsContent value="chat" className="space-y-3 pt-3">
        <Steps
          items={[
            'In Claude, ChatGPT or Grok, open the connector settings and add a custom (remote) MCP server.',
            `Use the URL ${URL}.`,
            'Leave authentication off. The server keeps no data and calls no paid APIs.'
          ]}
        />
      </TabsContent>
      <TabsContent value="json" className="pt-3">
        <Snippet code={JSON_CONFIG} />
      </TabsContent>
    </Tabs>
  );
}
