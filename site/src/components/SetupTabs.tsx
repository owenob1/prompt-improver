import type { ReactNode } from 'react';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

// Panels arrive as Astro slots (already rendered and highlighted), so this island only switches tabs.
// Every panel stays mounted in one grid cell: the tab area keeps the height of the tallest panel and
// nothing below it moves when the tab changes.
export function SetupTabs({ claudeCode, chat, json }: { claudeCode?: ReactNode; chat?: ReactNode; json?: ReactNode }) {
  const panels = [
    { value: 'claude-code', label: 'Claude Code', body: claudeCode },
    { value: 'chat', label: 'Chat apps', body: chat },
    { value: 'json', label: 'JSON config', body: json }
  ];
  return (
    <Tabs defaultValue="claude-code" className="gap-stack">
      <TabsList className="w-full">
        {panels.map((p) => (
          <TabsTrigger key={p.value} value={p.value}>
            {p.label}
          </TabsTrigger>
        ))}
      </TabsList>
      <div className="stack-cell">
        {panels.map((p) => (
          <TabsContent key={p.value} value={p.value} forceMount className="panel-inactive-hidden">
            {p.body}
          </TabsContent>
        ))}
      </div>
    </Tabs>
  );
}
