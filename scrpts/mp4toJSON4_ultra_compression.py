import cv2
import json
import os
import base64
import numpy as np

def rgb_to_hex(rgb):
    return '{:02X}{:02X}{:02X}'.format(rgb[0], rgb[1], rgb[2])

def quantize_colors(rgb_frame, div=64):
    return (rgb_frame // div) * div

def video_to_compressed_json(
    video_path,
    output_path,
    resize_to=(16, 16),
    max_frames=None,
    frame_rate=15,
    color_quantization_div=64
):
    if not os.path.exists(video_path):
        raise FileNotFoundError(f"Видео не найдено: {video_path}")

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise IOError("❌ Не удалось открыть видео.")

    width, height = resize_to
    palette = []
    palette_map = {}
    all_frames_indexed = []
    max_colors = 256

    total_pixels = 0
    frame_counter = 0
    
    while max_frames is None or frame_counter < max_frames:
        ret, frame = cap.read()
        if not ret:
            break
            
        frame_counter += 1
        
        frame = cv2.resize(frame, resize_to, interpolation=cv2.INTER_AREA)
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        
        if color_quantization_div > 1:
            rgb_frame = quantize_colors(rgb_frame, color_quantization_div)

        frame_indexed = []
        for row in rgb_frame:
            indexed_row = []
            for pixel in row:
                hex_color = rgb_to_hex(pixel)
                if hex_color not in palette_map:
                    if len(palette) >= max_colors:
                        # Находим ближайший цвет в палитре
                        min_dist = float('inf')
                        closest_color = None
                        for col in palette:
                            # Вычисляем евклидово расстояние между цветами
                            r1, g1, b1 = int(col[0:2], 16), int(col[2:4], 16), int(col[4:6], 16)
                            r2, g2, b2 = pixel[0], pixel[1], pixel[2]
                            dist = (r1 - r2)**2 + (g1 - g2)**2 + (b1 - b2)**2
                            if dist < min_dist:
                                min_dist = dist
                                closest_color = col
                        hex_color = closest_color
                    else:
                        palette_map[hex_color] = len(palette)
                        palette.append(hex_color)
                indexed_row.append(palette_map[hex_color])
            frame_indexed.append(indexed_row)
        all_frames_indexed.append(frame_indexed)
        total_pixels += width * height

    cap.release()
    
    print(f"📊 Статистика:")
    print(f"- Кадров: {len(all_frames_indexed)}")
    print(f"- Разрешение: {width}x{height}")
    print(f"- Всего пикселей: {total_pixels}")
    print(f"- Уникальных цветов: {len(palette)}")

    # Формируем бинарные RLE данные (без zlib)
    binary_data = bytearray()
    for frame in all_frames_indexed:
        flat_frame = [pixel for row in frame for pixel in row]
        i = 0
        while i < len(flat_frame):
            color_index = flat_frame[i]
            count = 1
            while i + count < len(flat_frame) and flat_frame[i + count] == color_index and count < 255:
                count += 1
            binary_data.append(color_index)
            binary_data.append(count)
            i += count

    # Преобразуем в Base64 (без zlib сжатия)
    frames_compressed = base64.b64encode(binary_data).decode('ascii')
    
    # Оценка размера
    uncompressed_size = len(binary_data)
    compressed_size = len(frames_compressed)
    compression_ratio = uncompressed_size / (total_pixels * 3)  # 3 байта на пиксель для RGB
    
    print(f"📦 Размер данных:")
    print(f"- Бинарные RLE: {uncompressed_size / 1024:.2f} KB")
    print(f"- Base64: {compressed_size / 1024:.2f} KB")
    print(f"- Коэффициент сжатия: {compression_ratio:.2f}x")
    print(f"- Экономия: {(1 - compression_ratio) * 100:.1f}%")

    result = {
        "width": width,
        "height": height,
        "frameRate": frame_rate,
        "frameCount": len(all_frames_indexed),
        "palette": palette,
        "compression": "binary_rle",  # Изменено для Lua скрипта
        "frames": frames_compressed
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False)

    print(f"✅ Готово! Сохранено в: {output_path}")
    return output_path

if __name__ == "__main__":
    video_to_compressed_json(
        video_path=r"C:\Users\User\Videos\Captures\D__Найдено “xdw”_rs.rbxl - Roblox Studio 2025-05-11 20-36-56.mp4",
        output_path=r"C:\Users\User\Videos\Captures\D__Найдено “xdw”_rs.rbxl - Roblox Studio 2025-05-11 20-36-56_3.json",
        resize_to=(256, 256),
        max_frames=None,  # Ограничьте для тестирования
        frame_rate=30,
        color_quantization_div=64
    )
