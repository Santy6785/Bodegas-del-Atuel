# Costo de escritura e Ã­ndice evaluado y descartado (Issue #99)

Mediciones ejecutadas sobre `bodegas_atuel_bench` (PostgreSQL 16) mediante bloques transaccionales aislados (`BEGIN; ... ROLLBACK;`) con `EXPLAIN (ANALYZE, BUFFERS)` para cuantificar el impacto de mantener Ã­ndices secundarios durante una carga masiva y verificar el descarte de un Ã­ndice de baja selectividad.

---

## 1. Costo de escritura: carga masiva con y sin Ã­ndices secundarios

Se midiÃ³ la inserciÃ³n de **20.000 comprobantes** sintÃ©ticos (`INSERT INTO comprobante ... SELECT FROM generate_series(1, 20000)`) bajo dos escenarios sobre `comprobante`:

1. **Sin Ã­ndices secundarios:** Ãºnicamente con `pk_comprobante` y las restricciones `FOREIGN KEY` (`id_cliente`, `id_sala`).
2. **Con Ã­ndices secundarios activos:** manteniendo simultÃ¡neamente `idx_comprobante_sala_fecha` (`btree (id_sala, fecha)`) e `idx_comprobante_fecha_inc` (`btree (fecha) INCLUDE (id_sala, total)`).

| MÃ©trica (`EXPLAIN (ANALYZE, BUFFERS)`) | Sin Ã­ndices secundarios | Con Ã­ndices secundarios | VariaciÃ³n / Impacto |
| :--- | ---: | ---: | ---: |
| **Tiempo nodo `Insert on comprobante` ** | **148,87 ms** | **644,74 ms** | **4,33Ã—** (+333 %) |
| **Tiempo total (incluyendo triggers FK)"¢ | **614,56 ms** | **1.069,08 ms** | **1,74Ã—** (+74 %) |
| **Buffers `shared hit`*( | 60.771 | 160.805 | +164,6 % |
| **Buffers `dirtied`** | 202 | 526 | +160,4 % |
| **Buffers `written`*( | 54 | 218 | **4,04Ã•** (+303,7 %) |

### Conclusiones sobre escritura

- Mantener dos Ã­ndices B-tree secundarios sobre `comprobante` multiplica por **4,33** el tiempo propio de inserciÃ³n y cuadruplica las pÃ¡ginas escritas (`written`), debido a la inserciÃ³n ordenada de claves y divisiÃ³n de pÃ¡ginas en ambos Ã¡rboles B-tree por cada fila nueva.
- Este resultado valida el orden de ejecuciÃ³n del esquema de migraciones: ejecutar la carga masiva inicial (`007_seed_masivo.sql`) antes de construir los Ã­ndices (`008_indices.sql`), evitando el costo incremental de actualizaciÃ³n por fila durante el poblamiento.

---

## 2. Ãndice evaluado y descartado: `idx_vino_tipo` sobre `vino(b¥Á¼¥€()M¥Õ¥•¹‘¼±¼Á±…¹Ñ•…‘¼•¸‘½Ì½‘•¥Í¥½¹•Ì¹µ‘€€£
œ€È¸ÄÈ¤°Í”•Ù…±×ÌÉ•…ÈÕ¸ƒµ¹‘¥”µÑÉ•”Í½‰É”±„½±Õµ¹„Ñ¥Á½€€¡Ñ¥Á½}Ù¥¹½€¤‘”±„Ñ…‰±„Ù¥¹½€è()ÍÅ°)IQ%9`¥‘á}Ù¥¹½}Ñ¥Á¼=8Ù¥¹¼€¡Ñ¥Á¼¤ì)91eiÙ¥¹¼ì()aA1%8€¡91ei°	UIL¤)M1P½‘}Ù¥¹¼°¹½µ‰É”°Ñ¥Á¼°ÁÉ•¥¼)I=4Ù¥¹¼)]!IÑ¥Á¼€ô€Ñ¥¹Ñ¼œì)€((ŒŒŒA±…¸½‰Ñ•¹¥‘¼()Ñ•áĞ)M•ÄM…¸½¸Ù¥¹¼€€¡½ÍĞôÀ¸ÀÀ¸¸Ä¸ÔÀÉ½İÌôÄÈİ¥‘Ñ ôÈà¤€¡…ÑÕ…°Ñ¥µ”ôÀ¸ÀÄÜ¸¸À¸ÀÈĞÉ½İÌôÄÈ±½½ÁÌôÄ¤(€¥±Ñ•Èè€¡Ñ¥Á¼€ô€Ñ¥¹Ñ¼œèéÑ¥Á½}Ù¥¹¼¤(€I½İÌI•µ½Ù•‰ä¥±Ñ•Èè€Èà(€	Õ™™•ÉÌèÍ¡…É•¡¥ĞôÄ)A±…¹¹¥¹œQ¥µ”è€À¸äÈÈµÌ)á•ÕÑ¥½¸Q¥µ”è€À¸ÀÔØµÌ)€((ŒŒŒ5½Ñ¥Ù½Ì‘•°‘•Í…ÉÑ”((Ä¸€¨©	…©„Í•±•Ñ¥Ù¥‘…è¨¨°‘½µ¥¹¥¼Ñ¥Á½}Ù¥¹½€…‘µ¥Ñ”ƒé¹¥…µ•¹Ñ”Õ…ÑÉ¼…Ñ•½Ëµ…Ì€¡Ñ¥¹Ñ¼œ°‰±…¹¼œ°É½Í…‘¼œ°•ÍÁÕµ…¹Ñ•€¤¸°ÁÉ•‘¥…‘¼]!IÑ¥Á¼€ô€Ñ¥¹Ñ¼€Í•±•¥½¹„€¨¨ÄÈ‘”€ĞÀ™¥±…Ì€ ÌÀ€”‘”±„Ñ…‰±„¤¨¨°µÕäÁ½È•¹¥µ„‘•°Õµ‰É…°‘½¹‘”Õ¸É•½ÉÉ¥‘¼Á½Èƒµ¹‘¥”ÍÕÁ•É„„Õ¸•Í…¹•¼Í•Õ•¹¥…°¸(È¸€¨©Q…‰±„É•Í¥‘•¹Ñ”•¸Õ¹„Í½±„Ã†Ú[˜H
Y™™\œÎˆÚ\™Y]LX
NŠŠˆÙÈ[Ø]0è[ÙÛÈHš[›ØØİ\H[ˆ0î›šXÛÈ›Ü]YHHĞ‹ˆ][^˜\ˆYİš[›×İ\ØØ›YØ\°ëXHHY\ˆ[Y[›ÜÈÜÈ0èYÚ[˜\È
0èYÚ[˜H[0ë[™XÙHX\È0èiİ¥¹„‘•°¡•…À¤•¸±Õ…È‘”É•Í½±Ù•È±„½¹ÍÕ±Ñ„•¸Õ¹„Í½±„±•ÑÕÉ„Í•Õ•¹¥…°‘”€À°ÀÔØµÍ€¸(Ì¸€¨©M½‰É•½ÍÑ¼Í¥¸É•Ñ½É¹¼è¨¨½¹Í•ÉÙ…È¥‘á}Ù¥¹½}Ñ¥Á½€‡Å…‘¥Ëµ„µ…¹Ñ•¹¥µ¥•¹Ñ¼•¸•ÍÉ¥ÑÕÉ…ÌÍ½‰É”Ù¥¹½€ä•ÍÁ…¥¼•¸‘¥Í¼Í¥¸ÅÕ”•°Á±…¹¥™¥…‘½È±¼•±¥©„•¸½¹ÍÕ±Ñ…ÌÉ•…±•Ì¸¸½¹Í•Õ•¹¥„°€¨©Í”‘•Í…ÉÑ„¨¨ä¹¼Í”¥¹±Õå”•¸‘ˆ½µ¥É…Ñ¥½¹Ì¼ÀÀá}¥¹‘¥•Ì¹ÍÅ±€
