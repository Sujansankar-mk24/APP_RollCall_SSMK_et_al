"""
Small geometry helpers: distances, and simplifying the outlines of counties
and warning areas so the app gets a few dozen points instead of thousands.
"""

import math


def distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Distance along the Earth's surface (haversine formula)."""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def simplify(points: list[list[float]], tolerance: float = 0.004) -> list[list[float]]:
    """
    Ramer-Douglas-Peucker: drop points that barely change the shape.
    `tolerance` is in degrees (0.004 is about 400 m), plenty for a phone map.
    """
    if len(points) < 4:
        return points

    def gap(p, a, b):
        # Distance from p to the line through a and b.
        (x, y), (x1, y1), (x2, y2) = p, a, b
        dx, dy = x2 - x1, y2 - y1
        if dx == dy == 0:
            return math.hypot(x - x1, y - y1)
        return abs(dy * x - dx * y + x2 * y1 - y2 * x1) / math.hypot(dx, dy)

    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        start, end = stack.pop()
        far, far_gap = None, tolerance
        for i in range(start + 1, end):
            g = gap(points[i], points[start], points[end])
            if g > far_gap:
                far, far_gap = i, g
        if far is not None:
            keep[far] = True
            stack += [(start, far), (far, end)]
    return [p for p, k in zip(points, keep) if k]


def geojson_rings(geometry: dict) -> list[list[list[float]]]:
    """
    The outer outline of each polygon in a GeoJSON Polygon or MultiPolygon,
    as lists of [latitude, longitude] (GeoJSON itself stores [longitude, latitude]).
    """
    if not geometry:
        return []
    kind, coords = geometry.get("type"), geometry.get("coordinates") or []
    polygons = [coords] if kind == "Polygon" else coords if kind == "MultiPolygon" else []
    rings = []
    for polygon in polygons:
        if polygon:
            outer = [[round(lat, 5), round(lon, 5)] for lon, lat in polygon[0]]
            rings.append(simplify(outer))
    return rings


def centroid(ring: list[list[float]]) -> tuple[float, float]:
    """A good-enough middle point of an outline (the average of its corners)."""
    lat = sum(p[0] for p in ring) / len(ring)
    lon = sum(p[1] for p in ring) / len(ring)
    return lat, lon


def in_area(lat: float, lon: float, area: tuple[float, float, float, float]) -> bool:
    west, south, east, north = area
    return south <= lat <= north and west <= lon <= east
