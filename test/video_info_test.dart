import 'package:flutter_test/flutter_test.dart';
import 'package:video_downloader/models/download_task.dart';
import 'package:video_downloader/models/format_option.dart';
import 'package:video_downloader/models/video_info.dart';

void main() {
  group('formats without codec metadata', () {
    // Shape taken verbatim from a real extractor that returns direct
    // progressive MP4s and reports no codec information at all. Treating the
    // missing keys as "no video and no audio" discarded every format and
    // surfaced a bogus "no downloadable streams" error.
    Map<String, dynamic> bareFormat(String id, int height) => {
          'format_id': id,
          'ext': 'mp4',
          'height': height,
          'protocol': 'https',
          'video_ext': 'mp4',
          'audio_ext': 'none',
          'url': 'https://example.invalid/$id.mp4',
        };

    final json = <String, dynamic>{
      'id': 'RfWwVLerNYY',
      'title': 'Example title',
      'duration': 8361,
      'formats': [
        bareFormat('240p', 240),
        bareFormat('360p', 360),
        bareFormat('480p', 480),
        bareFormat('720p_HD', 720),
      ],
    };

    test('are kept rather than filtered out', () {
      final info = VideoInfo.fromJson(json);

      expect(info.formats, hasLength(4));
      expect(info.downloadableFormats, hasLength(4));
      expect(info.isDrmProtected, isFalse);
    });

    test('are treated as complete streams needing no merge', () {
      final info = VideoInfo.fromJson(json);
      final best = info.formats.first;

      expect(best.formatId, '720p_HD');
      expect(best.codecsUnknown, isTrue);
      expect(best.isMuxed, isTrue);
      expect(info.muxedFormats, hasLength(4));
      expect(info.videoOnlyFormats, isEmpty);
      expect(info.audioOnlyFormats, isEmpty);
    });

    test('select without an unnecessary +bestaudio merge', () {
      final info = VideoInfo.fromJson(json);
      final selector = DownloadTask.buildSelector(
        info.formats.first,
        audioOnly: false,
      );

      expect(selector, '720p_HD');
    });

    test('fall back to the container for the codec label', () {
      final info = VideoInfo.fromJson(json);

      expect(info.formats.first.codecLabel, 'MP4');
    });
  });

  group('explicit codec metadata', () {
    test('an explicit "none" still marks a track absent', () {
      final videoOnly = FormatOption.fromJson({
        'format_id': '137',
        'ext': 'mp4',
        'height': 1080,
        'vcodec': 'avc1.640028',
        'acodec': 'none',
      });

      expect(videoOnly.hasVideo, isTrue);
      expect(videoOnly.hasAudio, isFalse);
      expect(videoOnly.isMuxed, isFalse);
      expect(videoOnly.codecsUnknown, isFalse);
      expect(videoOnly.codecLabel, 'avc1');
      expect(
        DownloadTask.buildSelector(videoOnly, audioOnly: false),
        '137+bestaudio/137',
      );
    });

    test('audio-only is recognised', () {
      final audio = FormatOption.fromJson({
        'format_id': '140',
        'ext': 'm4a',
        'vcodec': 'none',
        'acodec': 'mp4a.40.2',
      });

      expect(audio.isAudioOnly, isTrue);
      expect(audio.resolutionLabel, 'Audio only');
    });

    test('storyboard entries are dropped', () {
      final info = VideoInfo.fromJson({
        'id': 'x',
        'title': 'x',
        'formats': [
          {
            'format_id': 'sb0',
            'ext': 'mhtml',
            'protocol': 'mhtml',
            'vcodec': 'none',
            'acodec': 'none',
          },
          {
            'format_id': 'nothing',
            'ext': 'mp4',
            'vcodec': 'none',
            'acodec': 'none',
          },
          {'format_id': 'good', 'ext': 'mp4', 'height': 720},
        ],
      });

      expect(info.formats, hasLength(1));
      expect(info.formats.single.formatId, 'good');
    });
  });

  test('a playlist envelope resolves to its first entry', () {
    final info = VideoInfo.fromJson({
      '_type': 'playlist',
      'entries': [
        {
          'id': 'inner',
          'title': 'Inner video',
          'formats': [
            {'format_id': '1', 'ext': 'mp4', 'height': 480},
          ],
        },
      ],
    });

    expect(info.id, 'inner');
    expect(info.title, 'Inner video');
    expect(info.formats, hasLength(1));
  });

  test('DRM-only sources are flagged', () {
    final info = VideoInfo.fromJson({
      'id': 'x',
      'title': 'Protected',
      'formats': [
        {'format_id': '1', 'ext': 'mp4', 'height': 720, 'has_drm': true},
      ],
    });

    expect(info.isDrmProtected, isTrue);
    expect(info.downloadableFormats, isEmpty);
  });
}
