Attribute VB_Name = "RefreshEngineOutput"
Option Explicit

' ------------------------------------------------------------------------------
' RefreshEngineOutput
'
' Pulls the pricing engine's results into this workbook.
'
'   1. Run the engine from the repo folder:   julia --project=. run.jl
'      It writes CSV files (and any PNG charts) to  output/
'   2. Run the macro RefreshOutputs (Alt+F8 / Tools > Macro > Macros).
'
' Every output/<name>.csv is loaded into the sheet named <name>; the sheet is
' created if it does not exist. Only cell contents are replaced, so formats,
' Dashboard formulas and charts that point at those sheets keep working.
' Any output/*.png is placed on an "Images" sheet.
'
' The workbook must sit in the repo root, next to the output/ folder.
' Works on Excel for Mac and Windows (no Windows-only libraries).
' ------------------------------------------------------------------------------

Private Const OUTPUT_DIR As String = "output"
Private Const IMAGE_SHEET As String = "Images"
Private imageFailures As String      ' images AddPicture could not place

Public Sub RefreshOutputs()
    Dim sep As String, folder As String, f As String
    Dim csvs As New Collection, pngs As New Collection
    Dim ws As Worksheet, item As Variant, msg As String
    Dim nRows As Long, nCsv As Long, nPng As Long

    sep = Application.PathSeparator
    folder = ThisWorkbook.Path & sep & OUTPUT_DIR & sep

    ' List the folder (no wildcard: Dir patterns are unreliable on Mac).
    On Error Resume Next
    f = Dir(folder)
    On Error GoTo 0
    Do While Len(f) > 0
        Select Case LCase$(Right$(f, 4))
            Case ".csv": csvs.Add Left$(f, Len(f) - 4)
            Case ".png": pngs.Add f
        End Select
        f = Dir()
    Loop

    ' Fallback: refresh existing sheets whose CSV exists.
    If csvs.Count = 0 Then
        For Each ws In ThisWorkbook.Worksheets
            If Len(Dir(folder & ws.Name & ".csv")) > 0 Then csvs.Add ws.Name
        Next ws
    End If

    If csvs.Count = 0 And pngs.Count = 0 Then
        MsgBox "No CSV or PNG files found in:" & vbCrLf & folder & vbCrLf & vbCrLf & _
               "Run  julia --project=. run.jl  in the repo folder first, and keep this " & _
               "workbook in the repo root.", vbExclamation, "Refresh Outputs"
        Exit Sub
    End If

    Application.ScreenUpdating = False
    Application.Calculation = xlCalculationManual
    On Error GoTo Fail

    For Each item In csvs
        nRows = LoadCsv(folder & item & ".csv", SheetFor(CStr(item)))
        msg = msg & "  " & item & ".csv  (" & nRows & " rows)" & vbCrLf
        nCsv = nCsv + 1
    Next item

    If pngs.Count > 0 Then nPng = PlaceImages(folder, pngs)

    StampRefresh
    Application.Calculation = xlCalculationAutomatic
    Application.CalculateFull
    Application.ScreenUpdating = True

    MsgBox "Loaded " & nCsv & " CSV file(s):" & vbCrLf & msg & _
           IIf(nPng > 0, "Placed " & nPng & " image(s) on '" & IMAGE_SHEET & "'.", "") & _
           IIf(Len(imageFailures) > 0, vbCrLf & vbCrLf & "Could not place:" & vbCrLf & imageFailures, ""), _
           vbInformation, "Refresh Outputs"
    Exit Sub

Fail:
    Application.Calculation = xlCalculationAutomatic
    Application.ScreenUpdating = True
    MsgBox "Refresh stopped: " & Err.Description & vbCrLf & "Loaded so far:" & vbCrLf & msg, _
           vbCritical, "Refresh Outputs"
End Sub

' Read a whole CSV into a 2-D array and write it in one shot.
Private Function LoadCsv(path As String, ws As Worksheet) As Long
    Dim fh As Integer, text As String, lines() As String, fields() As String
    Dim data() As Variant, r As Long, c As Long, nR As Long, nC As Long

    fh = FreeFile
    Open path For Binary Access Read As #fh
    text = Space$(LOF(fh))
    Get #fh, , text
    Close #fh

    text = Replace(Replace(text, vbCrLf, vbLf), vbCr, vbLf)
    Do While Right$(text, 1) = vbLf
        text = Left$(text, Len(text) - 1)
    Loop
    ws.UsedRange.ClearContents
    If Len(text) = 0 Then Exit Function

    lines = Split(text, vbLf)
    nR = UBound(lines) + 1
    For r = 0 To nR - 1
        c = UBound(Split(lines(r), ",")) + 1
        If c > nC Then nC = c
    Next r

    ReDim data(1 To nR, 1 To nC)
    For r = 0 To nR - 1
        fields = Split(lines(r), ",")
        For c = 0 To UBound(fields)
            If r = 0 Then
                data(r + 1, c + 1) = fields(c)            ' header stays text
            Else
                data(r + 1, c + 1) = ParseCell(fields(c))
            End If
        Next c
    Next r

    ws.Range("A1").Resize(nR, nC).Value = data
    LoadCsv = nR - 1
End Function

' "" -> empty, yyyy-mm-dd -> date, plain number -> Double (Val ignores locale), else text.
Private Function ParseCell(ByVal s As String) As Variant
    s = Trim$(s)
    If Len(s) = 0 Then
        ParseCell = Empty
    ElseIf s Like "####-##-##" Then
        ParseCell = DateSerial(CInt(Left$(s, 4)), CInt(Mid$(s, 6, 2)), CInt(Right$(s, 2)))
    ElseIf IsPlainNumber(s) Then
        ParseCell = Val(s)
    Else
        ParseCell = s
    End If
End Function

' Accepts  [+-]digits[.digits][e[+-]digits]  (also .5 and 5.)
Private Function IsPlainNumber(ByVal s As String) As Boolean
    Dim i As Long, ch As String, digits As Boolean, dot As Boolean, ex As Boolean
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        Select Case ch
            Case "0" To "9"
                digits = True
            Case "+", "-"
                If i > 1 Then
                    If LCase$(Mid$(s, i - 1, 1)) <> "e" Then Exit Function
                End If
            Case "."
                If dot Or ex Then Exit Function
                dot = True
            Case "e", "E"
                If ex Or Not digits Then Exit Function
                ex = True
                digits = False             ' exponent needs its own digits
            Case Else
                Exit Function
        End Select
    Next i
    IsPlainNumber = digits
End Function

Private Function SheetFor(sheetName As String) As Worksheet
    On Error Resume Next
    Set SheetFor = ThisWorkbook.Worksheets(sheetName)
    On Error GoTo 0
    If SheetFor Is Nothing Then
        Set SheetFor = ThisWorkbook.Worksheets.Add( _
            After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
        SheetFor.Name = sheetName
    End If
End Function

' Replace every picture on the Images sheet with the PNGs from output/.
Private Function PlaceImages(folder As String, pngs As Collection) As Long
    Dim ws As Worksheet, i As Long, item As Variant, pic As Shape, y As Double
    Dim errText As String
    imageFailures = ""
    Set ws = SheetFor(IMAGE_SHEET)
    ws.Activate                      ' Mac Excel can reject AddPicture on an inactive sheet
    For i = ws.Shapes.Count To 1 Step -1
        ws.Shapes(i).Delete
    Next i
    ws.UsedRange.ClearContents
    ws.Cells(1, 1).Value = "Images from " & folder
    y = 30
    For Each item In pngs
        ' A picture that fails is listed at the end; the refresh carries on.
        Set pic = Nothing
        On Error Resume Next
        Set pic = ws.Shapes.AddPicture(folder & item, msoFalse, msoTrue, 10, y, -1, -1)
        errText = Err.Description
        Err.Clear
        On Error GoTo 0
        If pic Is Nothing Then
            imageFailures = imageFailures & "  " & item & " (" & errText & ")" & vbCrLf
        Else
            pic.LockAspectRatio = msoTrue
            If pic.Width > 720 Then pic.Width = 720
            pic.Name = Left$(CStr(item), Len(item) - 4)
            y = y + pic.Height + 30
            PlaceImages = PlaceImages + 1
        End If
    Next item
End Function

' Writes the time into a cell named LastRefresh, if the workbook has one.
Private Sub StampRefresh()
    On Error Resume Next
    ThisWorkbook.Names("LastRefresh").RefersToRange.Value = Now
    On Error GoTo 0
End Sub
