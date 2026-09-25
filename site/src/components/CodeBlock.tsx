import { CopyButton } from '@/components/CopyButton';

// A copyable value: the endpoint, the CLI command or a config snippet. Stacks on narrow screens,
// sits side by side from sm up.
export function CodeBlock({ value, label }: { value: string; label?: string }) {
  return (
    <div className="flex flex-col gap-stack-tight sm:flex-row sm:items-start sm:gap-inline">
      <pre className="min-w-0 flex-1 whitespace-pre-wrap rounded-md border bg-muted px-inset-x py-inset-y font-mono text-code">
        <code>{value}</code>
      </pre>
      <CopyButton value={value} label={label} />
    </div>
  );
}
