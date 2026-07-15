#!/usr/bin/env python3
"""Probe simples do limite por IP da API V2, sem dependências externas."""

from __future__ import annotations

import argparse
import json
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


@dataclass
class Result:
    index: int
    status: int | None
    elapsed: float
    retry_after: str
    body: str
    error: str = ""


def request(url: str, index: int) -> Result:
    started = time.monotonic()
    req = Request(url, headers={"Accept": "application/json"})
    try:
        with urlopen(req, timeout=20) as response:
            body = response.read().decode("utf-8", errors="replace")
            return Result(index, response.status, time.monotonic() - started,
                          response.headers.get("Retry-After", ""), body)
    except HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        return Result(index, error.code, time.monotonic() - started,
                      error.headers.get("Retry-After", ""), body)
    except (URLError, TimeoutError, OSError) as error:
        return Result(index, None, time.monotonic() - started, "", "", str(error))


def print_result(result: Result) -> None:
    suffix = f" retry-after={result.retry_after}s" if result.retry_after else ""
    print(f"req={result.index} status={result.status or 'ERR'} "
          f"time={result.elapsed:.3f}s{suffix}")
    if result.error:
        print(f"  error={result.error}")
    elif result.body:
        try:
            payload = json.loads(result.body)
            print(f"  response={json.dumps(payload, ensure_ascii=False)[:180]}")
        except json.JSONDecodeError:
            print(f"  response={result.body[:180]}")


def burst(url: str, count: int) -> list[Result]:
    with ThreadPoolExecutor(max_workers=count) as executor:
        futures = [executor.submit(request, url, index) for index in range(1, count + 1)]
        return sorted((future.result() for future in as_completed(futures)), key=lambda item: item.index)


def main() -> int:
    parser = argparse.ArgumentParser(description="Testa rate-limit por IP da API V2")
    parser.add_argument("--url", default="http://localhost:3330/api/v2/states")
    parser.add_argument("--requests", type=int, default=5)
    parser.add_argument("--wait-after", action="store_true",
                        help="aguarda Retry-After e testa uma requisição novamente")
    args = parser.parse_args()

    if args.requests < 1:
        parser.error("--requests deve ser maior que zero")

    print(f"burst url={args.url} simultaneas={args.requests}")
    results = burst(args.url, args.requests)
    for result in results:
        print_result(result)

    if not args.wait_after:
        return 0

    retry_values = [int(result.retry_after) for result in results if result.retry_after.isdigit()]
    wait_seconds = max(retry_values, default=60)
    print(f"aguardando {wait_seconds}s para testar a proxima janela...")
    time.sleep(wait_seconds)
    released = request(args.url, 1)
    print("apos-a-janela:")
    print_result(released)
    return 0 if released.status == 200 else 1


if __name__ == "__main__":
    raise SystemExit(main())
