import { CodeBlock } from '@/components/CodeBlock';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { SETUP } from '@/lib/site';

const PANELS = [
  { value: 'claude-code', label: 'Claude Code', body: <CodeBlock value={SETUP.claudeCode} /> },
  {
    value: 'chat',
    label: 'Chat apps',
    body: (
      <ol className="flex list-decimal flex-col gap-stack-tight pl-gutter text-small text-muted-foreground">
        {SETUP.chatSteps.map((step) => (
          <li key={step}>{step}</li>
        ))}
      </ol>
    )
  },
  { value: 'json', label: 'JSON config', body: <CodeBlock value={SETUP.json} /> }
];

// Every panel stays mounted in one grid cell, so the tab area always has the height of the
// tallest panel and nothing below it moves when the tab changes.
export function SetupTabs() {
  return (
    <Tabs defaultValue={PANELS[0]!.value} className="gap-stack">
      <TabsList className="w-full">
        {PANELS.map((p) => (
          <TabsTrigger key={p.value} value={p.value}>
            {p.label}
          </TabsTrigger>
        ))}
      </TabsList>
      <div className="stack-cell">
        {PANELS.map((p) => (
          <TabsContent key={p.value} value={p.value} forceMount className="panel-inactive-hidden">
            {p.body}
          </TabsContent>
        ))}
      </div>
    </Tabs>
  );
}
