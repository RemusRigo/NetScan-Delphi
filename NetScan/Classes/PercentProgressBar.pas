unit PercentProgressBar;

interface

uses
  System.SysUtils, System.Classes, Vcl.Controls, Vcl.Graphics, Winapi.Messages, Winapi.Windows;

type
   TPercentProgressBar = class(TGraphicControl)
   private
      FMin: Integer;
      FMax: Integer;
      FPosition: Integer;
      FBarColor: TColor;
      procedure SetMin(Value: Integer);
      procedure SetMax(Value: Integer);
      procedure SetPosition(Value: Integer);
      procedure SetBarColor(Value: TColor);
   protected
      procedure Paint; override;
      procedure Resize; override;
   public
      constructor Create(AOwner: TComponent); override;
   published
      property Align;
      property Anchors;
      property Font; // Controls the text appearance
      property Color; // Controls the background color
      property BarColor: TColor read FBarColor write SetBarColor default clHighlight;
      property Min: Integer read FMin write SetMin default 0;
      property Max: Integer read FMax write SetMax default 100;
      property Position: Integer read FPosition write SetPosition default 0;
   end;

procedure Register;

implementation

procedure Register;
begin
   RegisterComponents('Custom', [TPercentProgressBar]);
end;

constructor TPercentProgressBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 150;
  Height := 25;
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  FBarColor := clSkyBlue;
  Color := clBtnFace;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
end;

procedure TPercentProgressBar.Paint;
var
  WidthFactor: Double;
  BarWidth: Integer;
  Percent: Integer;
  TextStr: string;
  TextRect: TRect;
begin
  // 1. Draw Background
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);

  // 2. Draw Progress Fill
  if FMax > FMin then
  begin
    WidthFactor := (FPosition - FMin) / (FMax - FMin);
    // Bound check the factor between 0.0 and 1.0
    if WidthFactor < 0 then WidthFactor := 0;
    if WidthFactor > 1 then WidthFactor := 1;

    BarWidth := Round(Width * WidthFactor);

    if BarWidth > 0 then
    begin
      Canvas.Brush.Color := FBarColor;
      Canvas.FillRect(Rect(0, 0, BarWidth, Height));
    end;

    Percent := Round(WidthFactor * 100);
  end
  else
    Percent := 0;

  // 3. Draw Text Centered
  TextStr := Format('%d%%', [Percent]);
  Canvas.Font := Self.Font;
  Canvas.Brush.Style := bsClear; // Keep text background transparent

  TextRect := ClientRect;
  // This Win32 API function perfectly centers the text horizontally and vertically
  DrawText(Canvas.Handle, PChar(TextStr), Length(TextStr), TextRect,
    DT_CENTER or DT_VCENTER or DT_NOCLIP or DT_SINGLELINE);
end;

procedure TPercentProgressBar.Resize;
begin
  inherited;
  Invalidate; // Forces an instant redraw of the text the moment the size changes
end;

procedure TPercentProgressBar.SetMin(Value: Integer);
begin
  if FMin <> Value then
  begin
    FMin := Value;
    if FPosition < FMin then FPosition := FMin;
    Invalidate; // Forces component to repaint
  end;
end;

procedure TPercentProgressBar.SetMax(Value: Integer);
begin
  if FMax <> Value then
  begin
    FMax := Value;
    if FPosition > FMax then FPosition := FMax;
    Invalidate;
  end;
end;

procedure TPercentProgressBar.SetPosition(Value: Integer);
begin
  if Value < FMin then Value := FMin;
  if Value > FMax then Value := FMax;

  if FPosition <> Value then
  begin
    FPosition := Value;
    Invalidate; // Instantly redraws the bar with new progress and text
  end;
end;

procedure TPercentProgressBar.SetBarColor(Value: TColor);
begin
  if FBarColor <> Value then
  begin
    FBarColor := Value;
    Invalidate;
  end;
end;

end.
