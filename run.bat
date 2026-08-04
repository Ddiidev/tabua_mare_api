@taskkill /f /im tabua-mare-api.exe

v -cc msvc -o "./out/tabua-mare-api.exe" -g -d dev_static_gzip watch --only-watch=*.v,*.html,*.css,*.js --before "cls" run . 3330
