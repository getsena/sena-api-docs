# Requerimiento: Botón "Imprimir Página" en Ficha de Objeto

**Estado:** Borrador  
**Fecha:** 2026-06-02  
**Alcance MVP:** Ficha de Factura

---

## Contexto

Las fichas de objetos (facturas, clientes, aprobaciones, etc.) concentran información relevante que los usuarios necesitan compartir o archivar en formato físico o PDF. Actualmente no existe un mecanismo nativo para imprimir esta información de forma limpia, por lo que los usuarios recurren a la impresión del navegador, que incluye navegación, botones y otros elementos irrelevantes.

## Objetivo

Habilitar un botón **"Imprimir página"** en la ficha de cada objeto que genere una vista de impresión limpia con el resumen de la información contenida, adaptada a cada tipo de objeto.

---

## MVP: Ficha de Factura

### Ubicación del botón

- Ubicado en el área de acciones de la cabecera de la ficha, junto a otros controles existentes (editar, eliminar, etc.).
- Ícono: impresora (`printer`), con label "Imprimir" o tooltip "Imprimir página".
- Visible para todos los usuarios con acceso de lectura a la ficha.

### Comportamiento

Al hacer clic, el botón dispara `window.print()` abriendo el diálogo nativo del navegador, renderizando una vista de impresión que:

1. Oculta todos los elementos de navegación (sidebar, topbar, breadcrumbs).
2. Oculta los botones de acción de la ficha (incluyendo el propio botón de imprimir).
3. Muestra únicamente el contenido definido en la sección [Contenido a imprimir](#contenido-a-imprimir).
4. Aplica estilos limpios: fondo blanco, tipografía legible, sin sombras ni gradientes.

La implementación se basa en CSS `@media print` — no requiere generación de PDF en backend.

### Contenido a imprimir

#### Cabecera de la factura

| Campo | Fuente API (`InvoicePublic`) | Notas |
|---|---|---|
| Número de factura | `invoice_number` | Destacado, tamaño grande |
| Estado | `status` | Texto legible: Pendiente / Parcialmente pagada / Pagada / Castigada / Anulada |
| Dirección | `direction` | "Por cobrar" (receivable) / "Por pagar" (payable) |
| Monto | `amount` + `currency` | Formateado con separador de miles y símbolo de moneda |
| Fecha de vencimiento | `due_date` | Formato DD/MM/YYYY; vacío si es nulo |
| Empresa contraparte | relación `company` | Nombre + RUT (ver nota abajo) |
| Fecha de creación | `created` | Formato DD/MM/YYYY HH:mm |
| ID externo | `external_id` | Solo si tiene valor |

#### Notas internas

- Se muestran las notas internas tal como aparecen en la ficha actual.
- Se respeta el orden cronológico y el autor de cada nota.
- No se muestran controles de edición ni eliminación.

#### Análisis: ¿qué más incluir?

Más allá de cabecera + notas internas, se recomienda evaluar los siguientes elementos para el MVP:

**Incluir en MVP:**
- **Empresa contraparte (detalle):** nombre completo y RUT, no solo el link. Al imprimir, el link no tiene valor; el dato textual sí.
- **Documentos vinculados:** lista de DTEs/PDFs adjuntos (número de documento, tipo, fecha). Es información trazable y frecuentemente solicitada en contextos de auditoría.

**Diferir a iteración siguiente:**
- Historial de cambios de estado (timeline): útil, pero agrega complejidad de layout.
- Línea de cobros/pagos parciales: relevante para facturas con `status: partial`, pero requiere diseño adicional.
- QR o código de verificación del DTE: valioso para el contexto tributario chileno, pero depende de disponibilidad del dato en el DTE vinculado.

---

## Diseño de la vista de impresión

### Elementos visibles al imprimir

```
┌─────────────────────────────────────────────────────┐
│  [Logo Sena]                    [Fecha de impresión] │
├─────────────────────────────────────────────────────┤
│  FACTURA  #0001234                    [Estado: Paid] │
│  Por cobrar                                         │
│  Empresa: Comercial ABC S.A. · RUT: 76.123.456-7    │
│  Monto: CLP 1.250.000                               │
│  Vencimiento: 15/06/2026                            │
│  Creada: 01/06/2026 10:32                           │
│  ID externo: ERP-2026-0045  (si aplica)             │
├─────────────────────────────────────────────────────┤
│  DOCUMENTOS VINCULADOS                              │
│  · Factura Electrónica #33-1045  —  01/06/2026      │
├─────────────────────────────────────────────────────┤
│  NOTAS INTERNAS                                     │
│  [02/06/2026 · Sebastián] Confirmado pago pendiente │
│  [01/06/2026 · María]     Enviada a revisión        │
└─────────────────────────────────────────────────────┘
```

### Elementos ocultos al imprimir (`display: none` en `@media print`)

- Sidebar / navegación lateral
- Topbar / barra superior
- Breadcrumbs
- Todos los botones de acción (editar, eliminar, imprimir, etc.)
- Tabs de la ficha que no sean la principal
- Filtros, paginadores, tooltips

---

## Criterios de aceptación

- [ ] El botón "Imprimir" aparece en la ficha de factura para cualquier usuario con acceso de lectura.
- [ ] Al hacer clic, se abre el diálogo de impresión del navegador con la vista limpia.
- [ ] La vista impresa incluye: cabecera completa, documentos vinculados y notas internas.
- [ ] La vista impresa no incluye: navegación, botones de acción ni elementos interactivos.
- [ ] Los campos nulos o vacíos no muestran etiqueta vacía; se omiten o muestran "—".
- [ ] El estado se muestra en texto legible en español, no el valor de enum en inglés.
- [ ] La vista es legible en papel A4, orientación vertical.
- [ ] El botón es accesible vía teclado (`aria-label="Imprimir página"`).

---

## Extensibilidad

El patrón debe ser replicable a otras fichas. Para ello:

- Definir un componente `<PrintLayout>` (o equivalente según el framework) que envuelva el contenido imprimible y aplique los estilos `@media print`.
- Cada ficha de objeto define qué secciones pasa a `<PrintLayout>`.
- El botón de imprimir puede vivir en un componente genérico de toolbar de ficha.

**Próximos objetos sugeridos tras el MVP:**
1. Ficha de Cliente — datos de empresa, contactos, facturas asociadas.
2. Ficha de Aprobación — flujo de aprobación, firmantes, documentos.

---

## Fuera de alcance

- Generación de PDF en el servidor (puede evaluarse en una iteración futura).
- Envío del PDF por correo desde la ficha.
- Personalización del contenido imprimible por parte del usuario.
- Soporte para impresión de listas/tablas completas (aplica solo a fichas individuales).
