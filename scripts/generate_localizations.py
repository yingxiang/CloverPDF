#!/usr/bin/env python3
"""Generate CloverPDF String Catalogs from reviewed six-language translations."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCALES = ("en", "zh-Hans", "ko", "ja", "de", "ru")
T: dict[str, tuple[str, str, str, str, str, str]] = {
    "CloverPDF": ("CloverPDF", "CloverPDF", "CloverPDF", "CloverPDF", "CloverPDF", "CloverPDF"),
    "Merge PDFs": ("Merge PDFs", "合并 PDF", "PDF 병합", "PDFを結合", "PDFs zusammenführen", "Объединить PDF"),
    "PDF Merge": ("PDF Merge", "PDF合并", "PDF 병합", "PDF結合", "PDF-Zusammenführung", "Объединение PDF"),
    "PDF Batch Conversion": ("PDF Batch Conversion", "PDF批量转换", "PDF 일괄 변환", "PDF一括変換", "PDF-Stapelkonvertierung", "Пакетное преобразование PDF"),
    "PDF to Word": ("PDF to Word", "PDF 转 Word", "PDF를 Word로", "PDFをWordに変換", "PDF in Word", "PDF в Word"),
    "PDF to Word Task": ("PDF to Word", "PDF转Word", "PDF를 Word로", "PDFをWordに変換", "PDF in Word", "PDF в Word"),
    "Tasks": ("Tasks", "任务", "작업", "タスク", "Aufgaben", "Задачи"),
    "Delete Task Section": ("Delete Task Section", "删除任务分组", "작업 섹션 삭제", "タスクセクションを削除", "Aufgabenabschnitt löschen", "Удалить раздел задач"),
    "Delete all tasks in this section?": ("Delete all tasks in this section?", "确定删除此分组中的所有任务吗？", "이 섹션의 모든 작업을 삭제하시겠습니까?", "このセクションのすべてのタスクを削除しますか？", "Alle Aufgaben in diesem Abschnitt löschen?", "Удалить все задачи в этом разделе?"),
    "Settings": ("Settings", "设置", "설정", "設定", "Einstellungen", "Настройки"),
    "No PDFs selected": ("No PDFs selected", "未选择 PDF", "선택한 PDF 없음", "PDFが選択されていません", "Keine PDFs ausgewählt", "PDF не выбраны"),
    "No tasks": ("No tasks", "暂无任务", "작업 없음", "タスクはありません", "Keine Aufgaben", "Нет задач"),
    "Add PDF": ("Add PDF", "添加PDF", "PDF 추가", "PDFを追加", "PDF hinzufügen", "Добавить PDF"),
    "Clear": ("Clear", "清空", "지우기", "クリア", "Leeren", "Очистить"),
    "Page Range": ("Page Range", "页码范围", "페이지 범위", "ページ範囲", "Seitenbereich", "Диапазон страниц"),
    "Start: %lld": ("Start: %lld", "开始：%lld", "시작: %lld", "開始：%lld", "Start: %lld", "Начало: %lld"),
    "End: %lld": ("End: %lld", "结束：%lld", "끝: %lld", "終了：%lld", "Ende: %lld", "Конец: %lld"),
    "Premium required for batch conversion": ("Premium required for batch conversion", "批量转换需要高级版", "일괄 변환에는 프리미엄이 필요합니다", "一括変換にはプレミアムが必要です", "Premium für Stapelkonvertierung erforderlich", "Для пакетного преобразования нужна Premium-версия"),
    "Convert": ("Convert", "转换", "변환", "変換", "Konvertieren", "Преобразовать"),
    "Scanned PDF: OCR is not included": ("Scanned PDF: OCR is not included", "扫描版 PDF：当前不含 OCR", "스캔 PDF: OCR은 포함되지 않음", "スキャンPDF：OCRは含まれません", "Gescanntes PDF: OCR ist nicht enthalten", "Сканированный PDF: OCR не поддерживается"),
    "Add to Merge": ("Add to Merge", "添加到合并", "병합에 추가", "結合に追加", "Zum Zusammenführen hinzufügen", "Добавить к объединению"),
    "Convert to Word": ("Convert to Word", "转为 Word", "Word로 변환", "Wordに変換", "In Word konvertieren", "Преобразовать в Word"),
    "Premium": ("Premium", "高级版", "프리미엄", "プレミアム", "Premium", "Premium"),
    "Status": ("Status", "状态", "상태", "ステータス", "Status", "Статус"),
    "Premium Active": ("Premium Active", "高级版已激活", "프리미엄 활성화됨", "プレミアム有効", "Premium aktiv", "Premium активирован"),
    "Free": ("Free", "免费版", "무료", "無料", "Kostenlos", "Бесплатно"),
    "Free Conversions": ("Free Conversions", "免费转换", "무료 변환", "無料変換", "Kostenlose Konvertierungen", "Бесплатные преобразования"),
    "Unlock Premium": ("Unlock Premium", "解锁高级版", "프리미엄 잠금 해제", "プレミアムを解除", "Premium freischalten", "Разблокировать Premium"),
    "Output": ("Output", "输出", "출력", "出力", "Ausgabe", "Вывод"),
    "Default Folder": ("Default Folder", "默认文件夹", "기본 폴더", "デフォルトフォルダ", "Standardordner", "Папка по умолчанию"),
    "About": ("About", "关于", "정보", "情報", "Über", "О приложении"),
    "Application": ("Application", "应用", "응용 프로그램", "アプリケーション", "Anwendung", "Приложение"),
    "Privacy": ("Privacy", "隐私", "개인정보 보호", "プライバシー", "Datenschutz", "Конфиденциальность"),
    "Files stay on this Mac": ("Files stay on this Mac", "文件始终保留在此 Mac", "파일은 이 Mac에만 보관됩니다", "ファイルはこのMac内に保持されます", "Dateien bleiben auf diesem Mac", "Файлы остаются на этом Mac"),
    "PDF to Word Engine": ("PDF to Word Engine", "PDF 转 Word 引擎", "PDF-Word 엔진", "PDFからWord変換エンジン", "PDF-zu-Word-Engine", "Модуль PDF в Word"),
    "pdf2docx": ("pdf2docx", "pdf2docx", "pdf2docx", "pdf2docx", "pdf2docx", "pdf2docx"),
    "Clear Finished": ("Clear Finished", "清除已完成", "완료 항목 지우기", "完了項目を消去", "Abgeschlossene löschen", "Очистить завершенные"),
    "Batch Convert": ("Batch Convert", "批量转换", "일괄 변환", "一括変換", "Stapelkonvertierung", "Пакетное преобразование"),
    "Format": ("Format", "格式", "형식", "フォーマット", "Format", "Формат"),
    "PDF Document": ("PDF Document", "PDF 文档", "PDF 문서", "PDF書類", "PDF-Dokument", "Документ PDF"),
    "PNG Image": ("PNG Image", "PNG 图片", "PNG 이미지", "PNG画像", "PNG-Bild", "Изображение PNG"),
    "JPEG Image": ("JPEG Image", "JPEG 图片", "JPEG 이미지", "JPEG画像", "JPEG-Bild", "Изображение JPEG"),
    "Choose": ("Choose", "选择", "선택", "選択", "Auswählen", "Выбрать"),
    "Choose Batch Output Folder": ("Choose Batch Output Folder", "选择批量输出文件夹", "일괄 출력 폴더 선택", "一括出力フォルダを選択", "Ausgabeordner für Stapel wählen", "Выберите папку пакетного вывода"),
    "Cancel": ("Cancel", "取消", "취소", "キャンセル", "Abbrechen", "Отменить"),
    "Retry": ("Retry", "重试", "재시도", "再試行", "Wiederholen", "Повторить"),
    "Show in Finder": ("Show in Finder", "在 Finder 中显示", "Finder에서 보기", "Finderに表示", "Im Finder anzeigen", "Показать в Finder"),
    "Move Up": ("Move Up", "向上移动", "위로 이동", "上へ移動", "Nach oben verschieben", "Переместить вверх"),
    "Move Down": ("Move Down", "向下移动", "아래로 이동", "下へ移動", "Nach unten verschieben", "Переместить вниз"),
    "Delete": ("Delete", "删除", "삭제", "削除", "Löschen", "Удалить"),
    "Waiting": ("Waiting", "等待中", "대기 중", "待機中", "Wartet", "Ожидание"),
    "Validating": ("Validating", "正在校验", "검증 중", "検証中", "Wird geprüft", "Проверка"),
    "Processing": ("Processing", "处理中", "처리 중", "処理中", "Wird verarbeitet", "Обработка"),
    "Completed": ("Completed", "已完成", "완료됨", "完了", "Abgeschlossen", "Завершено"),
    "Failed": ("Failed", "失败", "실패", "失敗", "Fehlgeschlagen", "Ошибка"),
    "Cancelled": ("Cancelled", "已取消", "취소됨", "キャンセル済み", "Abgebrochen", "Отменено"),
    "Interrupted": ("Interrupted", "已中断", "중단됨", "中断", "Unterbrochen", "Прервано"),
    "Merge": ("Merge", "合并", "병합", "結合", "Zusammenführen", "Объединить"),
    "Save Merged File": ("Save Merged File", "保存合并文件", "병합 파일 저장", "結合ファイルを保存", "Zusammengeführte Datei sichern", "Сохранить объединенный файл"),
    "PDF Password": ("PDF Password", "PDF 密码", "PDF 암호", "PDFパスワード", "PDF-Passwort", "Пароль PDF"),
    "Remove": ("Remove", "移除", "제거", "削除", "Entfernen", "Удалить"),
    "%lld pages": ("%lld pages", "%lld 页", "%lld페이지", "%lldページ", "%lld Seiten", "%lld стр."),
    "%lld free conversions remaining": ("%lld free conversions remaining", "剩余 %lld 次免费转换", "무료 변환 %lld회 남음", "無料変換は残り%lld回", "%lld kostenlose Konvertierungen übrig", "Осталось бесплатных преобразований: %lld"),
    "Unlock CloverPDF Premium": ("Unlock CloverPDF Premium", "解锁 CloverPDF 高级版", "CloverPDF 프리미엄 잠금 해제", "CloverPDFプレミアムを解除", "CloverPDF Premium freischalten", "Разблокировать CloverPDF Premium"),
    "CloverPDF Premium is active": ("CloverPDF Premium is active", "CloverPDF 高级版已激活", "CloverPDF 프리미엄이 활성화되었습니다", "CloverPDFプレミアムが有効です", "CloverPDF Premium ist aktiv", "CloverPDF Premium активирован"),
    "Purchase Failed": ("Purchase Failed", "购买失败", "구매 실패", "購入に失敗しました", "Kauf fehlgeschlagen", "Покупка не удалась"),
    "Products are temporarily unavailable. Please try again later.": ("Products are temporarily unavailable. Please try again later.", "商品暂时不可用，请稍后再试。", "상품을 일시적으로 사용할 수 없습니다. 나중에 다시 시도하세요.", "商品を一時的に利用できません。後でもう一度お試しください。", "Produkte sind vorübergehend nicht verfügbar. Bitte später erneut versuchen.", "Товары временно недоступны. Повторите попытку позже."),
    "Unlimited PDF to Word conversion": ("Unlimited PDF to Word conversion", "无限 PDF 转 Word", "무제한 PDF-Word 변환", "PDFからWordへの変換が無制限", "Unbegrenzte PDF-zu-Word-Konvertierung", "Безлимитное преобразование PDF в Word"),
    "Batch conversion": ("Batch conversion", "批量转换", "일괄 변환", "一括変換", "Stapelkonvertierung", "Пакетное преобразование"),
    "Full task history and retry": ("Full task history and retry", "完整任务历史和重试", "전체 작업 기록 및 재시도", "完全なタスク履歴と再試行", "Vollständiger Aufgabenverlauf und Wiederholung", "Полная история задач и повтор"),
    "Future premium PDF tools": ("Future premium PDF tools", "未来新增高级 PDF 工具", "향후 프리미엄 PDF 도구", "今後追加されるプレミアムPDFツール", "Künftige Premium-PDF-Werkzeuge", "Будущие Premium-инструменты PDF"),
    "Best value": ("Best value", "最划算", "최고의 가치", "最もお得", "Bestes Angebot", "Лучшая цена"),
    "3-Month Subscription": ("3-Month Subscription", "3 个月订阅", "3개월 구독", "3か月サブスクリプション", "3-Monats-Abo", "Подписка на 3 месяца"),
    "6-Month Subscription": ("6-Month Subscription", "6 个月订阅", "6개월 구독", "6か月サブスクリプション", "6-Monats-Abo", "Подписка на 6 месяцев"),
    "1-Year Subscription": ("1-Year Subscription", "1 年订阅", "1년 구독", "1年サブスクリプション", "1-Jahres-Abo", "Подписка на 1 год"),
    "Lifetime Unlock": ("Lifetime Unlock", "永久解锁", "평생 잠금 해제", "永久解除", "Dauerhaft freischalten", "Пожизненная разблокировка"),
    "One purchase, permanent access": ("One purchase, permanent access", "一次购买，永久使用", "한 번 구매로 영구 사용", "一度の購入で永久アクセス", "Ein Kauf, dauerhafter Zugriff", "Одна покупка, постоянный доступ"),
    "Auto-renewable subscription": ("Auto-renewable subscription", "自动续期订阅", "자동 갱신 구독", "自動更新サブスクリプション", "Automatisch verlängerbares Abo", "Автовозобновляемая подписка"),
    "OK": ("OK", "好", "확인", "OK", "OK", "ОК"),
    "The PDF is damaged or unsupported.": ("The PDF is damaged or unsupported.", "PDF 已损坏或不受支持。", "PDF가 손상되었거나 지원되지 않습니다.", "PDFが破損しているか対応していません。", "Das PDF ist beschädigt oder wird nicht unterstützt.", "PDF поврежден или не поддерживается."),
    "This PDF requires a password.": ("This PDF requires a password.", "此 PDF 需要密码。", "이 PDF에는 암호가 필요합니다.", "このPDFにはパスワードが必要です。", "Dieses PDF benötigt ein Passwort.", "Для этого PDF требуется пароль."),
    "The PDF password is incorrect.": ("The PDF password is incorrect.", "PDF 密码错误。", "PDF 암호가 올바르지 않습니다.", "PDFのパスワードが正しくありません。", "Das PDF-Passwort ist falsch.", "Неверный пароль PDF."),
    "No pages are available to process.": ("No pages are available to process.", "没有可处理的页面。", "처리할 페이지가 없습니다.", "処理できるページがありません。", "Es sind keine Seiten zur Verarbeitung verfügbar.", "Нет страниц для обработки."),
    "The selected page range is invalid.": ("The selected page range is invalid.", "所选页码范围无效。", "선택한 페이지 범위가 잘못되었습니다.", "選択したページ範囲が無効です。", "Der ausgewählte Seitenbereich ist ungültig.", "Выбран неверный диапазон страниц."),
    "The output file could not be created.": ("The output file could not be created.", "无法创建输出文件。", "출력 파일을 만들 수 없습니다.", "出力ファイルを作成できませんでした。", "Die Ausgabedatei konnte nicht erstellt werden.", "Не удалось создать выходной файл."),
    "The Word converter is unavailable.": ("The Word converter is unavailable.", "Word 转换器不可用。", "Word 변환기를 사용할 수 없습니다.", "Word変換機能を利用できません。", "Der Word-Konverter ist nicht verfügbar.", "Конвертер Word недоступен."),
    "The converter returned an invalid response.": ("The converter returned an invalid response.", "转换器返回了无效响应。", "변환기가 잘못된 응답을 반환했습니다.", "変換機能から無効な応答が返されました。", "Der Konverter hat eine ungültige Antwort geliefert.", "Конвертер вернул неверный ответ."),
    "Conversion failed: %@": ("Conversion failed: %@", "转换失败：%@", "변환 실패: %@", "変換に失敗しました：%@", "Konvertierung fehlgeschlagen: %@", "Ошибка преобразования: %@"),
    "The task was cancelled.": ("The task was cancelled.", "任务已取消。", "작업이 취소되었습니다.", "タスクはキャンセルされました。", "Die Aufgabe wurde abgebrochen.", "Задача отменена."),
    "The task could not be completed.": ("The task could not be completed.", "无法完成任务。", "작업을 완료할 수 없습니다.", "タスクを完了できませんでした。", "Die Aufgabe konnte nicht abgeschlossen werden.", "Не удалось выполнить задачу."),
    "The source files must be added again.": ("The source files must be added again.", "需要重新添加源文件。", "원본 파일을 다시 추가해야 합니다.", "元のファイルを再度追加してください。", "Die Quelldateien müssen erneut hinzugefügt werden.", "Необходимо снова добавить исходные файлы."),
    "Enter the PDF password before retrying.": ("Enter the PDF password before retrying.", "请先输入 PDF 密码再重试。", "재시도하기 전에 PDF 암호를 입력하세요.", "再試行する前にPDFパスワードを入力してください。", "Geben Sie vor dem erneuten Versuch das PDF-Passwort ein.", "Введите пароль PDF перед повторной попыткой."),
    "Premium is required for this conversion.": ("Premium is required for this conversion.", "此转换需要高级版。", "이 변환에는 프리미엄이 필요합니다.", "この変換にはプレミアムが必要です。", "Für diese Konvertierung ist Premium erforderlich.", "Для этого преобразования нужна Premium-версия."),
    "暂时无法加载解锁产品，请稍后再试": ("Unable to load products. Please try again later.", "暂时无法加载解锁产品，请稍后再试", "상품을 불러올 수 없습니다. 나중에 다시 시도하세요.", "商品を読み込めません。後でもう一度お試しください。", "Produkte können nicht geladen werden. Bitte später erneut versuchen.", "Не удалось загрузить товары. Повторите попытку позже."),
    "购买正在处理中，请稍后再检查解锁状态": ("The purchase is pending. Check the unlock status later.", "购买正在处理中，请稍后再检查解锁状态", "구매 처리 중입니다. 나중에 잠금 해제 상태를 확인하세요.", "購入を処理中です。後で解除状態をご確認ください。", "Der Kauf wird verarbeitet. Prüfen Sie den Status später erneut.", "Покупка обрабатывается. Проверьте статус позже."),
    "购买验证失败，请稍后再试": ("Purchase verification failed. Please try again later.", "购买验证失败，请稍后再试", "구매 확인에 실패했습니다. 나중에 다시 시도하세요.", "購入の検証に失敗しました。後でもう一度お試しください。", "Kaufprüfung fehlgeschlagen. Bitte später erneut versuchen.", "Не удалось проверить покупку. Повторите попытку позже."),
}
INFO_T: dict[str, tuple[str, str, str, str, str, str]] = {
    "CFBundleDisplayName": ("CloverPDF", "CloverPDF", "CloverPDF", "CloverPDF", "CloverPDF", "CloverPDF"),
    "CFBundleName": ("CloverPDF", "CloverPDF", "CloverPDF", "CloverPDF", "CloverPDF", "CloverPDF"),
    "PDF Document": ("PDF Document", "PDF 文档", "PDF 문서", "PDF書類", "PDF-Dokument", "Документ PDF"),
}


def catalog(strings: dict[str, tuple[str, ...]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, values in strings.items():
        result[key] = {
            "localizations": {
                locale: {"stringUnit": {"state": "translated", "value": value}}
                for locale, value in zip(LOCALES, values, strict=True)
            }
        }
    return {"sourceLanguage": "en", "strings": result, "version": "1.0"}


def main() -> None:
    resources = ROOT / "CloverPDF" / "Resources"
    resources.mkdir(parents=True, exist_ok=True)
    output = resources / "Localizable.xcstrings"
    output.write_text(json.dumps(catalog(T), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    info_output = resources / "InfoPlist.xcstrings"
    info_output.write_text(json.dumps(catalog(INFO_T), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
