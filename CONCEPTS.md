# Concepts

Shared domain vocabulary for this project - entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Palette Management

### Palette
A named set of colors that can be rendered in the matching grid or edited through palette management.

### Preset Palette
A built-in palette that is read-only in the editor and must be duplicated before it can become editable.

### User Palette
A saved editable palette created, renamed, duplicated, or deleted by the user.

### Active Palette
The palette selection currently shared between the grid page and palette management page.

## Palette And Swatch Measurement

### Palette Color
A single printable color entry within a palette, distinct from its measured behavior under any specific light source or printer setup.

### Printer Profile
The printer/material/settings context that produced a set of printed swatches, used to keep measurements and predictions from different output conditions separate.

### Illuminant
A named lighting condition used to observe or measure printed colors, such as white, red, green, blue, or low-pressure sodium light.

### Illuminant Response
The apparent brightness behavior of a printed palette color under one illuminant for one printer profile.

### Response Vector
The collection of illuminant responses for a palette color, used to compare that color against target brightness values from source images.

### Mapped Image
A generated printable image whose pixels are selected palette colors chosen to approximate different source-image brightness targets under different illuminants.
