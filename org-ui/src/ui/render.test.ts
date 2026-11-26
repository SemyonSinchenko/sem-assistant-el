import { isValidElement, type ReactNode } from 'react';
import { describe, expect, it } from 'vitest';
import { renderInline } from './OrgRender';

function text(nodes: ReactNode[]): string {
  return nodes
    .map((n) => (typeof n === 'string' ? n : isValidElement(n) ? text([(n.props as { children?: ReactNode }).children].flat()) : ''))
    .join('');
}

describe('renderInline', () => {
  it('terminates on nested markup and links with descriptions', () => {
    const s = 'see [[https://a.org][the *docs*]] and *bold /it/* then =code= and [[https://b.org][b]] end';
    expect(text(renderInline(s))).toBe('see the docs and bold it then code and b end');
  });
  it('renders bare urls and keeps unsafe link text', () => {
    expect(text(renderInline('go https://x.org/a, or [[javascript:alert(1)][x]]'))).toBe('go https://x.org/a, or x');
  });
});
