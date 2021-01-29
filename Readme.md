Qué es Ruby?
Ruby es un lenguaje de programación orientado a objetos interpretado que se utiliza a menudo para el desarrollo web. También ofrece muchas funciones de secuencias de comandos para procesar texto sin formato y archivos serializados, o administrar tareas del sistema. Es simple, sencillo y extensible.

Características de Ruby
Sintaxis simple
Funciones orientadas a objetos normales (por ejemplo, clases, llamadas a métodos)
Funciones avanzadas orientadas a objetos (p. Ej., Combinación, método singleton)
Sobrecarga del operador
Manejo de excepciones
Iteradores y cierres
Recolección de basura
Carga dinámica de archivos de objeto (en algunas arquitecturas)
Altamente portátil (funciona en muchas plataformas compatibles tipo Unix / POSIX, así como Windows, macOS, etc.) cf. https://github.com/ruby/ruby/blob/master/doc/contributing.rdoc#label-Platform+Maintainers
Cómo conseguir Ruby
Para obtener una lista completa de formas de instalar Ruby, incluido el uso de herramientas de terceros como rvm, consulte:

https://www.ruby-lang.org/en/downloads/

Git
El espejo del árbol de fuentes de Ruby se puede verificar con el siguiente comando:

$ git clone https://github.com/ruby/ruby.git
Hay algunas otras ramas en desarrollo. Pruebe el siguiente comando para ver la lista de ramas:

$ git ls-remote https://github.com/ruby/ruby.git
También puede utilizar https://git.ruby-lang.org/ruby.git (maestro real de la fuente de Ruby) si es un committer.

Subversión
Las ramas estables para versiones anteriores de Ruby se pueden verificar con el siguiente comando:

$ svn co https://svn.ruby-lang.org/repos/ruby/branches/ruby_2_6/ ruby
Pruebe el siguiente comando para ver la lista de ramas:

$ svn ls https://svn.ruby-lang.org/repos/ruby/branches/
Página de inicio de Ruby
https://www.ruby-lang.org/

Lista de correo
Hay una lista de correo para discutir Ruby. Para suscribirse a esta lista, envíe la siguiente frase:

subscribe
en el cuerpo del correo (sin asunto) a la dirección ruby-talk-request@ruby-lang.org .

Cómo compilar e instalar
Si desea utilizar Microsoft Visual C ++ para compilar Ruby, lea win32 / README.win32 en lugar de este documento.

Si ./configureno existe o es anterior a configure.ac, ejecute autoconfpara (re) generar configure.

Ejecutar ./configure, que generará config.hy Makefile.

Es posible que se agreguen algunos indicadores del compilador de C de forma predeterminada, dependiendo de su entorno. Especifique optflags=..y warnflags=..según sea necesario para anularlos.

Edítelo include/ruby/defines.hsi lo necesita. Por lo general, este paso no será necesario.

Elimine la marca de comentario ( #) antes de los nombres de los módulos de ext/Setup(o agregue los nombres de los módulos si no están presentes), si desea vincular módulos de forma estática.

Si no desea compilar módulos de extensión no estáticos (probablemente en arquitecturas que no permiten la carga dinámica), elimine la marca de comentario de la línea " #option nodynamic" en ext/Setup.

Por lo general, este paso no será necesario.

Corre make.

En Mac, configure la variable de entorno RUBY_CODESIGN con una identidad de firma. Utiliza la identidad para firmar rubybinarios. Ver también codeign (1).
Opcionalmente, ejecute ' make check' para comprobar si el intérprete de Ruby compilado funciona bien. Si ve el mensaje " check succeeded", su Ruby funciona como debería (con suerte).

Ejecutar ' make install'.

Este comando creará los siguientes directorios e instalará archivos en ellos.

${DESTDIR}${prefix}/bin
${DESTDIR}${prefix}/include/ruby-${MAJOR}.${MINOR}.${TEENY}
${DESTDIR}${prefix}/include/ruby-${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}
${DESTDIR}${prefix}/lib
${DESTDIR}${prefix}/lib/ruby
${DESTDIR}${prefix}/lib/ruby/${MAJOR}.${MINOR}.${TEENY}
${DESTDIR}${prefix}/lib/ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}
${DESTDIR}${prefix}/lib/ruby/site_ruby
${DESTDIR}${prefix}/lib/ruby/site_ruby/${MAJOR}.${MINOR}.${TEENY}
${DESTDIR}${prefix}/lib/ruby/site_ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}
${DESTDIR}${prefix}/lib/ruby/vendor_ruby
${DESTDIR}${prefix}/lib/ruby/vendor_ruby/${MAJOR}.${MINOR}.${TEENY}
${DESTDIR}${prefix}/lib/ruby/vendor_ruby/${MAJOR}.${MINOR}.${TEENY}/${PLATFORM}
${DESTDIR}${prefix}/lib/ruby/gems/${MAJOR}.${MINOR}.${TEENY}
${DESTDIR}${prefix}/share/man/man1
${DESTDIR}${prefix}/share/ri/${MAJOR}.${MINOR}.${TEENY}/system
Si la versión de la API de Ruby es ' xyz ', ${MAJOR}es ' x ', ${MINOR}es ' y ' y ${TEENY}es ' z '.

NOTA : una pequeña parte de la versión de la API puede ser diferente de una de las versiones del programa de Ruby

Puede que tenga que ser un superusuario para instalar Ruby.

Si no puede compilar Ruby, envíe el informe de error detallado con el registro de errores y el tipo de máquina / sistema operativo, para ayudar a otros.

Es posible que algunas bibliotecas de extensión no se compilen debido a la falta de bibliotecas externas y / o encabezados necesarios, entonces deberá ejecutar ' make distclean-ext' para eliminar la configuración anterior después de instalarlas en tal caso.

Proceso de copiar
Ver el archivo COPIA .

Retroalimentación
Las preguntas sobre el lenguaje Ruby se pueden hacer en la lista de correo Ruby-Talk ( https://www.ruby-lang.org/en/community/mailing-lists ) o en sitios web como ( https://stackoverflow.com ).

Los errores deben informarse en https://bugs.ruby-lang.org . Lea HowToReport para obtener más información.

Contribuyendo
Ver el archivo CONTRIBUTING.md

El autor
Ruby fue diseñado y desarrollado originalmente por Yukihiro Matsumoto (Matz) en 1995.

matz@ruby-lang.org
