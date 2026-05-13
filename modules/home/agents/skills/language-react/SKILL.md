---
name: language-react
description: React-specific development rules and idioms. Invoke when editing or reviewing React code.
user-invocable: false
---

# React

Rules for React code.

## 1. No useEffect

`useEffect` is banned for application logic. Every `useEffect` call is a potential bug — stale
closures, missing deps, race conditions, unnecessary re-renders. Use these replacements:

- **Value derived from state/props** — compute inline or with `useMemo`; do not sync via effect.
- **Data fetching** — use a query library (React Query, SWR); do not fetch in effects.
- **User-triggered action** — call from the event handler; do not watch a trigger state in an
  effect.
- **One-time external setup** — use the `useMountEffect` escape hatch (below).
- **Reset component on prop change** — pass a changing `key` prop to force remount; do not reset
  state in an effect.

### useMountEffect

For one-time synchronization with external systems (analytics, third-party widgets, non-React DOM
libraries). This is the only acceptable effect pattern, and it should be rare.

```tsx
function useMountEffect(effect: () => void | (() => void)) {
  const ran = useRef(false);
  useEffect(() => {
    if (ran.current) return;
    ran.current = true;
    return effect();
  }, []);
}
```

## References

- [You Might Not Need an Effect](https://react.dev/learn/you-might-not-need-an-effect)
