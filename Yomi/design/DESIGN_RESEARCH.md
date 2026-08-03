# YOMI — Research de diseño, UX/UI y competencia
_Investigación para decidir la dirección visual. Julio 2026._

---

## 0. Resumen ejecutivo (leé esto primero)

Investigué las mejores apps de lectura (manga, manhwa, novelas, ebooks), qué aman y qué odian sus usuarios, y la estética/UX de las apps mejor diseñadas y más usadas en general. La conclusión es clara y va en contra de mi primera propuesta:

**No ganás con "otra grilla oscura minimalista" —eso ya lo tenés y lo tienen todos. Ganás con tres cosas que ningún competidor resuelve bien a la vez: (1) personalización profunda y hermosa, (2) un reader de calidad científica, y (3) un chrome que usa lo bueno de iOS 26 sin caer en lo malo.**

Tu instinto ("que el usuario personalice hasta el fondo") no es un capricho: es exactamente donde está la oportunidad de mercado. La app de lectura más querida de la última década (Moon+ Reader) es amada *precisamente* por eso. Y ninguna app de manga iOS lo hace con buen gusto.

Los 7 pilares de la dirección recomendada están en la sección 10.

---

## 1. Panorama competitivo

### Apps de manga/manhwa en iOS (tus rivales directos)

| App | Rating / tracción | Qué aman | Qué odian |
|-----|------|----------|-----------|
| **Tachimanga** | 4.8★ · ~4.9k reviews | Ads solo al abrir (no interrumpen la lectura), no molesta con el "paga la versión pro", CBZ/EPUB, servidores propios (Komga), "el mejor lector que probé", "el lifetime sin ads vale 10 veces" | Errores de Cloudflare, límite de 10 descargas/día en free, en iPad los webtoons se ven con zoom excesivo y barras negras |
| **Aidoku** | Free, open-source, en beta | Libertad, customización, privacidad, sources de la comunidad, categorías, temas visuales, modos de lectura; v0.8 sumó gestos iOS 26 e **Insights de tiempo de lectura** y vista de lista | Todavía beta, iCloud sync inestable, instalación con fricción (TestFlight/AltStore/Discord) |
| **Paperback** | Popular entre power users | Interfaz moderna, sources modulares, liviano, extensible, muy customizable | Curva de setup: los principiantes sufren antes de que todo funcione |
| **Manga Storm** | Veterano | Control avanzado, caché offline, estable | Interfaz **anticuada** frente a apps nuevas |

**Lectura clave:** el techo de calidad en iOS lo pone Tachimanga (4.8★) y su fórmula ganadora es simple — **no arruinar la lectura con ads y ser confiable.** Aidoku es tu competidor filosófico más cercano (open-source, plugins, insights) pero está en beta y con fricción de instalación. Nadie tiene aún el combo "pulido + hermoso + novelas + sin fricción".

### El estándar de Android

- **Mihon / Tachiyomi** — free, open-source, extensiones, personalización profunda. Es el patrón de oro para power users y la referencia que todos copian. Su fuerza es la libertad total; su debilidad, que es "de nerds" y visualmente austero.

### Apps oficiales / masivas

- **Manga Plus** (Shueisha) — oficial, gratis, capítulos simultáneos en varios idiomas. La gente lo ama por **legitimidad y velocidad de lanzamiento.**
- **Webtoon** (Naver) — el gigante: 64M+ usuarios, 10M diarios / 35M mensuales. Domina manhwa/webtoons, pero está **muy criticado**: arquitectura de información confusa ("Originals" vs "Canvas" son tipos de contenido, no funciones), perfil de usuario pobre, ads en medio de la historia que rompen la lectura, y contenido bueno tras paywall. Es grande por catálogo, no por UX.
- **Wattpad** — 100M+ descargas, foco en historias de usuarios/fanfic.

### Ebooks y novelas (donde YOMI es casi único en iOS)

| App | Qué aman | Qué odian |
|-----|----------|-----------|
| **Apple Books** | "Se siente como un objeto diseñado, no una tienda con lectura pegada al lado". La mejor **tipografía**, page-turn y vista de biblioteca. El referente de experiencia de lectura pura. | Gestión de biblioteca básica que no escala, sin edición de metadata, sin soporte MOBI/AZW |
| **Kindle** | Catálogo enorme, sync entre dispositivos, fuentes de accesibilidad (OpenDyslexic) | DRM propietario, audiolibros en app separada, encierro en Amazon |
| **Kobo** | EPUB nativo (incluso sideload), libros + audiolibros juntos, suscripción Kobo Plus | Algunos libros exclusivos, menos integrado con Apple |
| **Moon+ Reader** | **Personalización extrema** (fuente, tamaño, color de fondo, interlineado). Usuarios que se quedan **6+ años** "porque acomodo todo como quiero" | UI algo cargada para casuales |
| **ReadEra** | Simpleza, opciones según formato (PDF vs CBR) | Menos potente para power users |
| **LNReader** (Android) | 500+ sources de novelas, base de tu Formato B | Sin equivalente iOS — **esa es tu ventaja exclusiva** |

**Lectura clave:** cero apps en el App Store combinan lector de manga + novelas con sistema de plugins. Tu diferenciador de novelas es real y defendible.

---

## 2. Qué AMAN los usuarios (patrones que se repiten)

1. **Personalización de la lectura.** Es el elogio #1 y recurrente. Fuente, tamaño, color de fondo, interlineado, márgenes, gestos, orientación, paginar con botones de volumen, modos de lectura, dark/OLED. Es literalmente la razón de existir (y de retener) de Moon+ Reader.
2. **Nada de ads intrusivos.** Cuando una app respeta la lectura (Tachimanga: ads solo al abrir), los usuarios lo celebran y pagan el lifetime.
3. **"Continue reading" que de verdad recuerda dónde quedaste.** Cuando funciona, es sagrado.
4. **Descargas offline.**
5. **Interfaz limpia e intuitiva, biblioteca bien organizada.**
6. **Legitimidad y velocidad de contenido** (Manga Plus).
7. **Sync entre dispositivos** (cuando anda).
8. **Tipografía hermosa** (Apple Books).
9. **Insights / tiempo de lectura** (Aidoku lo sumó; vos ya lo tenés).

## 3. Qué ODIAN los usuarios (patrones que se repiten)

1. **Ads excesivos e intrusivos** — el problema #1 lejos. Ads en medio del capítulo, sin botón de cerrar, que obligan a reiniciar la app, que llevan a la store al tocar la pantalla.
2. **"Continue reading" roto** — no guarda la posición, el botón es inútil.
3. **Capítulos que no cargan, duplicados, o muestran contenido de otro manga; conteos de capítulos inconsistentes.**
4. **Fallos de Cloudflare / conexión.**
5. **Monetización agresiva** — monedas, paywalls, pocos puntos por ver ads.
6. **Arquitectura de información confusa / navegación pobre** (Webtoon).
7. **Fricción de instalación / setup** (Paperback, Aidoku con extensiones y TestFlight).
8. **Sync con bugs.**
9. **Problemas de display en iPad / webtoon** (zoom, recorte).

**Implicancia para YOMI:** tu modelo (sin ads, plugins que instala el usuario, confiable) ya te pone por encima de la mayoría de las quejas. **Protegé eso como oro.** Los dos riesgos a vigilar de tu lado: (a) fiabilidad del "continue reading" y de la carga de capítulos, (b) fricción al instalar plugins la primera vez.

---

## 4. Estética y UX de las mejores apps (en general)

**Las apps más queridas por su diseño comparten un ADN:** minimalistas en distracciones, máximas en la acción principal, y el **contenido es el protagonista** — no el chrome.

- **Apple Books** — "objeto diseñado, no tienda con lectura al lado". Tipografía impecable, animación de página, vista de biblioteca placentera.
- **Things 3** — dos Apple Design Awards. "Diseño minimalista espectacular" *y* perfectamente funcional. Elegancia = quitar, no agregar.
- **Bear** — escritura limpia, elegante, rapidísima.
- **Craft** — bloques, cards, layouts limpios; se siente pulido y fácil de leer.

**Apple Design Awards 2025** (a qué le da premios Apple hoy): CapWords, Play, Speechify (accesibilidad TTS en 50+ idiomas), Watch Duty, y en **Visuals & Graphics** ganó *Feather: Draw in 3D*. Apple premia **claridad, interacción con propósito, inclusividad** — no fuegos artificiales.

**Tendencias 2025 confirmadas:** layouts minimalistas + acentos de color audaces, profundidad sutil por capas, glassmorphism (Liquid Glass), microinteracciones **con propósito**, y **dark mode dado por sentado** (no ofrecerlo es desventaja competitiva).

---

## 5. iOS 26 "Liquid Glass": la oportunidad escondida

Esto es importante porque tu app es iOS 26 y ya usás `.glassEffect()`. El veredicto de **Nielsen Norman Group** (la autoridad más respetada en usabilidad) es lapidario:

> "Liquid Glass está agrietado… iOS 26 prioriza el espectáculo sobre la usabilidad."

Los problemas concretos que documentan:

- **Transparencia = ilegibilidad.** Texto sobre imágenes/otro texto, contraste tan bajo como **1.5:1** cuando el mínimo WCAG es 4.5:1.
- **Targets táctiles más chicos y apretados.**
- **Controles impredecibles** que aparecen/colapsan según contexto (no se pueden "aprender").
- **Animaciones sin significado** que distraen y "marean" a la décima vez.

**Cómo lo convertís en ventaja de YOMI:** usá Liquid Glass **con bisturí** — solo en chrome flotante (barra de tabs, overlay del reader) y **nunca encima de texto o contenido**. Contraste alto siempre, controles estables, animación solo cuando comunica algo. Donde Apple exageró, vos hacés lo correcto: eso se percibe como calidad premium. Es un diferenciador gratis.

---

## 6. Personalización como estrategia (no solo estética)

La data respalda tu intuición de "que el usuario personalice todo":

- **+70%** de los usuarios ya considera la personalización una **expectativa básica**.
- **89%** de los marketers reporta que la personalización sube ingresos.
- El **dark theme ya se da por sentado**; no tenerlo bien resuelto es desventaja.
- La personalización **sube retención** — la app "se siente como que evoluciona conmigo".
- Contrapeso: cuidar privacidad/confianza (en tu caso es fácil, todo es local).

**Conclusión:** convertir la personalización en una **feature estrella con identidad propia** (no un menú de settings escondido) es a la vez diferenciador y motor de retención. Ninguna app de manga lo hace con buen gusto. Ahí está tu bandera.

---

## 7. Tipografía de lectura (specs con respaldo científico)

Para el reader de novelas, estos números vienen de investigación (Bringhurst, Baymard, eye-tracking):

- **Largo de línea:** 50–75 caracteres, **66 es el ideal**. (Novatos ~45, expertos hasta 80.) Líneas de +80 se saltean **41% más**.
- **Tamaño de cuerpo:** ≥16px (web) / 18pt es cómodo para sesiones largas.
- **Interlineado:** 1.4–1.5× (140% es el sweet spot); **por debajo de 1.4× cansa**.
- **Márgenes laterales generosos:** reducen fatiga y ayudan al escaneo.
- **Espacio entre párrafos ≈ tamaño de fuente.**
- Buena tipografía = **+20% de precisión de lectura y −30% de fatiga visual**.

**Estado de YOMI:** tus defaults (18pt, interlineado 1.6, temas sepia/dark/AMOLED) ya están **muy bien**. Lo que falta exponer al usuario: **control de ancho de línea / márgenes** (para respetar los 50–75 CPL en iPad y landscape) y elección de fuente. Eso te pone a nivel Moon+ Reader.

---

## 8. Discovery y home (patrón Netflix / Spotify)

- Netflix y Spotify organizan el home en **cards + estanterías (rows)** que se vuelven más personalizadas a medida que bajás.
- **+80%** de lo que se ve en Netflix llega por **recomendación, no búsqueda.**
- Diferenciador clave de Netflix: **personalización del thumbnail** (misma serie, distinta portada según el usuario).

**Implicancia:** un **home editorial con estanterías** (Continue, Up next, Por categoría, Recomendados) genera más engagement y descubrimiento que una grilla uniforme — valida la dirección "editorial" que exploramos. **Pero** dejalo **opcional**: los power users de Mihon quieren su grilla pelada. La respuesta es: home editorial por defecto, con opción de "biblioteca simple".

---

## 9. Gamificación y retención (modelo Duolingo)

- **Streaks:** +60% de compromiso (aversión a la pérdida — "no cortes la cadena").
- **Leaderboards/XP:** +40% de engagement. **Badges:** +30% de completitud.
- Mecánicas **en capas** para distintas etapas del usuario (logros del día 1 → algo que proteger → metas raras de largo plazo).
- En lectura: streaks + badges + barras de progreso = **loop de dopamina → hábito → retención**.

**Estado de YOMI:** ya tenés Insights, streaks y calendario de actividad. Tu principio ("gamificación ligera, sin presión") es sano y correcto. Sumá detalles humanos (ej. "congelar la racha") y dejá lo social/competitivo como opción futura, nunca impuesto.

---

## 10. Recomendación de dirección para YOMI

Síntesis de todo lo anterior en 7 pilares. Esta es la respuesta a "no me decido":

1. **Contenido protagonista, chrome silencioso** — el principio de Apple Books/Things/Bear se queda. Pero (aprendiendo de tu feedback) el chrome silencioso **no** significa "grilla oscura aburrida": significa que la UI no compite con las portadas ni con el tema del usuario.

2. **Personalización profunda como FEATURE ESTRELLA** — un "Appearance Studio" con identidad: presets listos (Midnight / Paper / Sepia / AMOLED / custom) + acento + forma de portada + densidad de grilla + tipografía. Presets para los que no quieren pensar, control total para los que sí. **Este es el diferenciador que nadie tiene bien.**

3. **Home editorial y descubrimiento** — Continue como héroe + estanterías (Up next, por categoría, recomendados), con opción de "biblioteca simple" para power users.

4. **Reader de calidad científica** — clavar tipografía (50–75 CPL, interlineado 1.4–1.6, márgenes generosos, control de ancho), gestos, modos de lectura, inmersivo. Acá se gana o se pierde una app de lectura.

5. **Liquid Glass bien hecho** — glass solo en chrome flotante, nunca sobre texto; contraste alto; controles estables; animación con propósito. Hacer bien lo que Apple hizo mal = percepción premium.

6. **Básicos impecables y sin ads** — proteger tu ventaja: cero ads, "continue reading" confiable, carga de capítulos robusta, y **reducir la fricción de instalar el primer plugin** (onboarding guiado).

7. **Gamificación humana** — streaks/insights sin presión, opcionales, con toques amables.

### Identidad visual sugerida
Un lienzo **neutro y premium** (no necesariamente negro: temable) + **tipografía con carácter** para títulos (una display distintiva que le dé marca) + **portadas tratadas como arte** (héroe grande, color ambiente extraído de la portada) + **el acento del usuario** como único color de marca. La firma de YOMI vive en tipografía, ritmo, el reader y momentos como el ícono — no en un color fijo.

### Próximos pasos propuestos
1. Definir el **Appearance Studio** (los presets + qué ejes se pueden tocar) — es el corazón de la identidad.
2. Rediseñar el **Reader** primero (manga + novela) con los specs de la sección 7 — es el alma de la app.
3. Rediseñar la **Home/Library** editorial con opción simple.
4. Diseñar el **ícono** (blocker de App Store) alineado a la identidad.
5. Screenshots de App Store que muestren el Appearance Studio como estrella.

---

## 11. Fuentes

- Digital Citizen — Best Manga Reader Apps for iPhone/iPad: https://www.digitalcitizen.life/best-manga-reader-apps-for-iphone-ipad/
- Tachimanga — App Store: https://apps.apple.com/us/app/tachimanga/id6447486175
- Aidoku — GitHub / sitio: https://github.com/Aidoku/Aidoku · https://aidoku.app/help/faq/
- OneJailbreak — Aidoku review: https://onejailbreak.com/blog/aidoku-manga-reader/
- Reddit/LiveAnime — Best manga reader recommendations: https://www.liveanime.org/post/best-manga-reader-app-reddit
- App Store reviews (Paperback / MangaBuddy / MangaToon) sobre ads y UI: https://apps.apple.com/us/app/paperback-comic-manga-reader/id1626613373?see-all=reviews
- TWiT — Kobo vs Kindle vs Apple Books vs Libby: https://twit.tv/posts/tech/kobo-vs-kindle-vs-apple-books-vs-libby-which-book-app-best-you
- getBookShelves — Apple Books alternatives 2026: https://getbookshelves.app/guides/apple-books-alternatives-2026/
- SaaSHub — ReadEra vs Moon Reader: https://www.saashub.com/compare-readera-vs-moon-reader
- AppleInsider — Inside Apple Books: https://appleinsider.com/inside/ios-18/tips/inside-apple-books----the-best-app-for-book-lovers
- Webtoon (platform) — Wikipedia (tracción): https://en.wikipedia.org/wiki/Webtoon_(platform)
- Medium — Redesigning Webtoon App (UX case study): https://medium.com/@saragj92/case-study-redesigning-webtoon-app-1956b007d212
- Apple — 2025 Apple Design Awards winners: https://www.apple.com/newsroom/2025/06/apple-unveils-winners-and-finalists-of-the-2025-apple-design-awards/
- Apple Developer — 2024 ADA (Things/Bear context): https://developer.apple.com/design/awards/2024/
- Nielsen Norman Group — Liquid Glass Is Cracked (iOS 26): https://www.nngroup.com/articles/liquid-glass/
- Muzli — iOS app design inspiration/trends: https://muz.li/inspiration/ios-app-examples/
- Chop Dawg — UI/UX trends 2025: https://www.chopdawg.com/ui-ux-design-trends-in-mobile-apps-for-2025/
- UXPin — Optimal line length (50–75): https://www.uxpin.com/studio/blog/optimal-line-length-for-readability/
- Justinmind — Line spacing best practices: https://www.justinmind.com/blog/best-ux-practices-for-line-spacing/
- GCC Marketing — Personalized UX, key to app success 2025: https://www.gcc-marketing.com/en/blog/personalized-user-experiences-the-key-to-mobile-app-success-in-2025/
- OpenLoyalty — Duolingo gamification mechanics: https://www.openloyalty.io/insider/how-duolingos-gamification-mechanics-drive-customer-loyalty
- ReadBrew — Reading apps with streaks and badges: https://www.readbrew.app/blog/best-reading-apps-with-streaks-and-badges
- Spotify Engineering — Personalizing home with ML: https://engineering.atspotify.com/2020/1/for-your-ears-only-personalizing-spotify-home-with-machine-learning
