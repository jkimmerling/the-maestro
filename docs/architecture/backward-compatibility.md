# Backward Compatibility Assessment

- Legacy helper scripts removed in Story 0.6; unified Provider-based scripts replace them.
- Internal `TheMaestro.Auth` utilities retained to support provider implementations.
- Named sessions preserve compatibility via `TheMaestro.SavedAuthentication`.

No public API breaks anticipated for consumers using `TheMaestro.Provider`.

