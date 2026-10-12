"""
Download the demo photos and video into sample_media/.

Every file comes from Wikimedia Commons and is public domain or under a
Creative Commons license. The script asks Commons for each file's author and
license and writes them to sample_media/CREDITS.md, so credit is always correct.

Run from the backend folder:
    python -m scripts.download_samples
Files that are already downloaded are skipped.
"""

import re
import shutil
from html import unescape
import subprocess
import sys
import time
from pathlib import Path

import requests  # installed with ultralytics; unlike urllib it brings its own SSL certificates

from app.config import SAMPLE_MEDIA_DIR

API_URL = "https://commons.wikimedia.org/w/api.php"
HEADERS = {"User-Agent": "RollCall/1.0 (Congressional App Challenge student project)"}
PHOTO_WIDTH = 1280  # Commons serves resized copies; 1280 px is plenty for analysis

# (file name we save as, exact Commons title, what it's used for)
PHOTOS = [
    ("grass_fire_crew.jpg", "Firefighters Battle Grass Fire 1.jpg", "grass fire with firefighters"),
    ("grass_fire_line.jpg", "Firefighters battle grass fire 3.jpg", "grass fire line"),
    ("prescribed_burn_texas.jpg", "Prescribed burn at Texas refuge - DPLA - 2db92d044882f87fedb918edff8cbe04.jpg", "field fire in Texas"),
    ("controlled_burn_smoke.jpg", "Controlled burn and fire break with smoke.jpg", "field fire with smoke"),
    ("smoke_plume.jpg", "Smoke plume from SoCal wildfire October 2007.jpg", "distant smoke plume"),
    ("night_fire_crew.jpg", "Silhouette of firefighters on the night in front of the flame.jpg", "fire at night with people"),
    ("night_fire_training.jpg", "JBSA-Randolph firefighters conduct night fire training 161017-F-XF990-0035.jpg", "structure fire at night"),
    ("flooded_intersection.jpg", "FEMA - 37220 - Flooded intersection of roads in Texas.jpg", "flooded intersection"),
    ("crash_medical.jpg", "Medical evacuation after car accident Kawartha Lakes Ontario.jpg", "vehicle crash with injured person"),
    ("downed_power_lines.jpg", "Storm Downed power lines and trees from Storm Sandy (8138919297).jpg", "storm damage, downed lines"),
]

# Videos: (file name, Commons title, which smaller copy to download, seconds to keep, what it's used for)
VIDEOS = [
    ("grass_fire_clip.mp4", "Burning grass and trees - 5 shot sequence (49802810636).webm", "480p.vp9.webm", 30, "grass fire video"),
]


def polite_get(url: str, **kwargs) -> requests.Response:
    """GET that waits and retries if Commons says we're asking too fast (HTTP 429)."""
    for attempt in range(5):
        response = requests.get(url, headers=HEADERS, **kwargs)
        if response.status_code != 429:
            response.raise_for_status()
            return response
        time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"Wikimedia Commons is rate-limiting us; wait a minute and run again ({url})")


def commons_info(titles: list[str], video: bool) -> dict[str, dict]:
    """
    Ask the Commons API, in ONE request, for each file's download links,
    author and license. Returns {title: info}.
    """
    params = {
        "action": "query",
        "format": "json",
        "titles": "|".join(f"File:{t}" for t in titles),
        "prop": "videoinfo" if video else "imageinfo",
    }
    if video:
        params["viprop"] = "url|derivatives|extmetadata"
    else:
        params["iiprop"] = "url|extmetadata"
        params["iiurlwidth"] = PHOTO_WIDTH
    data = polite_get(API_URL, params=params, timeout=30).json()["query"]

    # Commons may rewrite titles slightly (e.g. underscores); map them back.
    renamed = {n["to"]: n["from"] for n in data.get("normalized", [])}
    results = {}
    for page in data["pages"].values():
        title = renamed.get(page["title"], page["title"]).removeprefix("File:")
        if "missing" in page:
            raise RuntimeError(f"Commons file not found: {title}")
        results[title] = page["videoinfo" if video else "imageinfo"][0]
    return results


def plain_text(html: str) -> str:
    """Commons returns author names as HTML; keep just the text."""
    return unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", html)).strip())


def credit_line(file_name: str, title: str, info: dict) -> str:
    meta = info.get("extmetadata", {})
    author = plain_text(meta.get("Artist", {}).get("value", "Unknown"))
    license_name = meta.get("LicenseShortName", {}).get("value", "see source")
    return f"| {file_name} | {author} | {license_name} | {info['descriptionurl']} |"


def download(url: str, destination: Path) -> None:
    """
    Download one file. Uses the `curl` program when available: Wikimedia's
    media server rate-limits Python's HTTP library much more strictly than curl.
    """
    curl = shutil.which("curl")
    if curl:
        result = subprocess.run(
            [curl, "--silent", "--show-error", "--fail", "--location", "--retry", "4", "--retry-delay", "10",
             "--user-agent", HEADERS["User-Agent"], "--output", str(destination), url],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            return
        destination.unlink(missing_ok=True)
    destination.write_bytes(polite_get(url, timeout=120).content)


def convert_to_mp4(source: Path, destination: Path, seconds: int) -> None:
    """
    Commons stores video as WebM, which iPhones can't play. Convert it to an
    H.264 MP4 (no audio) with ffmpeg, which comes bundled in the imageio-ffmpeg package.
    """
    import imageio_ffmpeg

    subprocess.run(
        [imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-i", str(source),
         "-t", str(seconds), "-an", "-c:v", "libx264", "-crf", "26", "-preset", "veryfast", "-pix_fmt", "yuv420p",
         "-movflags", "+faststart", str(destination)],
        check=True,
    )


def main() -> None:
    credits = [
        "# Sample media credits",
        "",
        "Downloaded from Wikimedia Commons by `scripts/download_samples.py` for RollCall's demo data.",
        "Photos are resized copies; the video is trimmed and converted to MP4. No other changes were made.",
        "",
        "| File | Author | License | Source |",
        "|---|---|---|---|",
    ]

    photo_info = commons_info([p[1] for p in PHOTOS], video=False)
    video_info = commons_info([v[1] for v in VIDEOS], video=True)

    for file_name, title, purpose in PHOTOS:
        destination = SAMPLE_MEDIA_DIR / file_name
        info = photo_info[title]
        credits.append(credit_line(file_name, title, info))
        if destination.exists():
            print(f"  already have {file_name}")
            continue
        print(f"  downloading {file_name} ({purpose})")
        download(info.get("thumburl") or info["url"], destination)
        time.sleep(1)

    for file_name, title, derivative, seconds, purpose in VIDEOS:
        destination = SAMPLE_MEDIA_DIR / file_name
        info = video_info[title]
        credits.append(credit_line(file_name, title, info))
        if destination.exists():
            print(f"  already have {file_name}")
            continue
        print(f"  downloading {file_name} ({purpose})")
        source_url = next(
            (d["src"] for d in info.get("derivatives", []) if d.get("transcodekey") == derivative),
            info["url"],
        )
        temporary = destination.with_suffix(".download.webm")
        download(source_url, temporary)
        convert_to_mp4(temporary, destination, seconds)
        temporary.unlink()

    (SAMPLE_MEDIA_DIR / "CREDITS.md").write_text("\n".join(credits) + "\n")
    print(f"Done. {len(PHOTOS) + len(VIDEOS)} files in {SAMPLE_MEDIA_DIR}")


def missing_files() -> list[str]:
    """Names of sample files that haven't been downloaded yet."""
    names = [p[0] for p in PHOTOS] + [v[0] for v in VIDEOS]
    return [n for n in names if not (SAMPLE_MEDIA_DIR / n).exists()]


if __name__ == "__main__":
    try:
        main()
    except (requests.RequestException, RuntimeError) as error:
        sys.exit(f"Download failed ({error}). Check your internet connection and try again.")
