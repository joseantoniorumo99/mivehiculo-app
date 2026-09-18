# El plugin de ML Kit referencia los reconocedores de chino, japonés, coreano
# y devanagari aunque la app solo lleve el latino. R8 los echa en falta al
# minificar; no se usan nunca, así que se le dice que no avise.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
