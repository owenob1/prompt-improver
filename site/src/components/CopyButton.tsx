import { Check, Copy } from 'lucide-react';
import { useState } from 'react';
import { Button } from '@/components/ui/button';

// The visible label never changes, so the button keeps its width; only the icon swaps.
// A polite live region tells screen readers the copy happened.
export function CopyButton({ value, label = 'Copy' }: { value: string; label?: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // Clipboard can be blocked (insecure context, permissions); the value stays selectable on the page.
    }
  }

  return (
    <Button type="button" variant="outline" size="sm" onClick={copy} className="shrink-0 self-start">
      {copied ? <Check aria-hidden /> : <Copy aria-hidden />}
      {label}
      <span className="sr-only" aria-live="polite">
        {copied ? 'Copied' : ''}
      </span>
    </Button>
  );
}
