const char *s1 = "café not utf8";  /* stray 0xe9 */
int x = 0x8a; // literal byte below
const char bad[] = { ÿ, þ, 0 };
int ok = 42;
