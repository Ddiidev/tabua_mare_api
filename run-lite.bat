@taskkill /f /im tabua-mare-api.exe

v -cc msvc -g -o "./out/tabua-mare-api.exe" -d using_sqlite -d dev_static_gzip watch --only-watch=*.v,*.html,*.css,*.js --before "taskkill /f /im tabua-mare-api.exe" --before "cls"  run . 3330
