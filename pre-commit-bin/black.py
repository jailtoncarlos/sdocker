#!/usr/bin/python3

import os
import shlex
import subprocess
import sys


def get_changed_files():
    with subprocess.Popen(
        shlex.split("git diff --name-only origin/master.."),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ) as process:
        files = []
        for line in iter(process.stdout.readline, b""):
            output = line.rstrip().decode()
            if output.endswith(".py"):
                files.append(output)
    return files


def main():
    if "--all" in sys.argv:
        apps = "."
        if "-v" in sys.argv or "--verbose" in sys.argv:
            sys.stdout.write(">>> Todos os arquivos serão avaliados")
    else:
        files = get_changed_files()
        apps = " ".join(file for file in files if os.path.exists(file))
        if "-v" in sys.argv or "--verbose" in sys.argv:
            sys.stdout.write(">>> Os seguintes arquivos serão avaliados:")
            sys.stdout.write("\n".join(files))
            sys.stdout.write("\n")

    if apps:
        result = os.system(f"autopep8 -r --ignore E501 -i --exit-code {apps}")
        if result:
            sys.stderr.write("Formatação realizada")
            sys.exit(1)
        else:
            sys.stdout.write(">>>>>> Nenhuma formatação realizada...\n")
    else:
        sys.stdout.write(">>>>>> Nenhuma formatação realizada...\n")


if __name__ == "__main__":
    main()
