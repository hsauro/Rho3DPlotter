unit Rho3DJsonUtils;

{
  JSON helpers for TRho3DPlot persistence, following the conventions of the
  2D component's uPlotJsonUtils (kept as a separate unit so the two
  components stay independent and can live in one application):

    * colours are "#AARRGGBB" strings;
    * every reader takes a default, returned when the object is nil, the key
      is missing or the value has the wrong type, so older and newer files
      load gracefully.

  Additions for 3D data: NaN is written as JSON null (NaN is not valid JSON)
  and read back from null; vectors and matrices of doubles.
}

interface

uses
  System.SysUtils,
  System.JSON,
  System.UITypes;

type
  TDoubleMatrix = TArray<TArray<Double>>;

function AlphaColorToHex(C: TAlphaColor): string;
function HexToAlphaColor(const S: string; Default: TAlphaColor): TAlphaColor;

function JBool (const Obj: TJSONObject; const Key: string; const Default: Boolean): Boolean;
function JInt  (const Obj: TJSONObject; const Key: string; const Default: Integer): Integer;
/// Reads a number; null reads as NaN.
function JFloat(const Obj: TJSONObject; const Key: string; const Default: Double): Double;
function JStr  (const Obj: TJSONObject; const Key: string; const Default: string): string;
function JColor(const Obj: TJSONObject; const Key: string; const Default: TAlphaColor): TAlphaColor;
function JObj  (const Obj: TJSONObject; const Key: string): TJSONObject;
function JArr  (const Obj: TJSONObject; const Key: string): TJSONArray;
/// Vector of doubles (null entries -> NaN). Missing key -> nil.
function JVector(const Obj: TJSONObject; const Key: string): TArray<Double>;
/// Matrix (array of row arrays). Missing key -> nil.
function JMatrix(const Obj: TJSONObject; const Key: string): TDoubleMatrix;

procedure JPutBool (const Obj: TJSONObject; const Key: string; const Value: Boolean);
procedure JPutInt  (const Obj: TJSONObject; const Key: string; const Value: Integer);
/// Writes a number, or null for NaN / infinity.
procedure JPutFloat(const Obj: TJSONObject; const Key: string; const Value: Double);
procedure JPutStr  (const Obj: TJSONObject; const Key: string; const Value: string);
procedure JPutColor(const Obj: TJSONObject; const Key: string; const Value: TAlphaColor);
procedure JPutVector(const Obj: TJSONObject; const Key: string; const Values: array of Double);
procedure JPutMatrix(const Obj: TJSONObject; const Key: string; const Values: TDoubleMatrix);

function FloatToJson(const V: Double): TJSONValue;
function JsonToFloat(const V: TJSONValue; const Default: Double): Double;

implementation

uses
  System.Generics.Collections,
  System.Math;

function AlphaColorToHex(C: TAlphaColor): string;
begin
  Result := Format('#%.8x', [Cardinal(C)]);
end;

function HexToAlphaColor(const S: string; Default: TAlphaColor): TAlphaColor;
var
  Hex: string;
  V: Int64;
begin
  Result := Default;
  Hex := S.Trim;
  if Hex.StartsWith('#') then
    Hex := Hex.Substring(1);
  case Length(Hex) of
    6: Hex := 'FF' + Hex;
    8: ;
  else
    Exit;
  end;
  if TryStrToInt64('$' + Hex, V) then
    Result := TAlphaColor(V);
end;

function DoubleToJsonText(const V: Double): string;
var
  digits: Integer;
  fs: TFormatSettings;
begin
  // shortest text that reads back as exactly the same double, so a saved
  // plot reloads bit-for-bit (TJSONNumber.Create(Double) keeps 15 digits)
  fs := TFormatSettings.Invariant;
  for digits := 15 to 17 do
  begin
    Result := FloatToStrF(V, ffGeneral, digits, 0, fs);
    if StrToFloat(Result, fs) = V then
      Exit;
  end;
end;

function FloatToJson(const V: Double): TJSONValue;
begin
  if IsNan(V) or IsInfinite(V) then
    Result := TJSONNull.Create
  else
    Result := TJSONNumber.Create(DoubleToJsonText(V));
end;

function JsonToFloat(const V: TJSONValue; const Default: Double): Double;
begin
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsDouble
  else if V is TJSONNull then
    Result := NaN
  else
    Result := Default;
end;

function JBool(const Obj: TJSONObject; const Key: string; const Default: Boolean): Boolean;
var
  V: TJSONValue;
begin
  Result := Default;
  if Obj = nil then Exit;
  V := Obj.GetValue(Key);
  if V is TJSONBool then
    Result := TJSONBool(V).AsBoolean;
end;

function JInt(const Obj: TJSONObject; const Key: string; const Default: Integer): Integer;
var
  V: TJSONValue;
begin
  Result := Default;
  if Obj = nil then Exit;
  V := Obj.GetValue(Key);
  if V is TJSONNumber then
    Result := TJSONNumber(V).AsInt;
end;

function JFloat(const Obj: TJSONObject; const Key: string; const Default: Double): Double;
begin
  if Obj = nil then
    Exit(Default);
  Result := JsonToFloat(Obj.GetValue(Key), Default);
end;

function JStr(const Obj: TJSONObject; const Key: string; const Default: string): string;
var
  V: TJSONValue;
begin
  Result := Default;
  if Obj = nil then Exit;
  V := Obj.GetValue(Key);
  if V is TJSONString then
    Result := TJSONString(V).Value;
end;

function JColor(const Obj: TJSONObject; const Key: string; const Default: TAlphaColor): TAlphaColor;
begin
  Result := HexToAlphaColor(JStr(Obj, Key, ''), Default);
end;

function JObj(const Obj: TJSONObject; const Key: string): TJSONObject;
var
  V: TJSONValue;
begin
  Result := nil;
  if Obj = nil then Exit;
  V := Obj.GetValue(Key);
  if V is TJSONObject then
    Result := TJSONObject(V);
end;

function JArr(const Obj: TJSONObject; const Key: string): TJSONArray;
var
  V: TJSONValue;
begin
  Result := nil;
  if Obj = nil then Exit;
  V := Obj.GetValue(Key);
  if V is TJSONArray then
    Result := TJSONArray(V);
end;

function ArrayToVector(const A: TJSONArray): TArray<Double>;
var
  i: Integer;
begin
  Result := nil;
  if A = nil then Exit;
  SetLength(Result, A.Count);
  for i := 0 to A.Count - 1 do
    Result[i] := JsonToFloat(A.Items[i], NaN);
end;

function JVector(const Obj: TJSONObject; const Key: string): TArray<Double>;
begin
  Result := ArrayToVector(JArr(Obj, Key));
end;

function JMatrix(const Obj: TJSONObject; const Key: string): TDoubleMatrix;
var
  A: TJSONArray;
  i: Integer;
begin
  Result := nil;
  A := JArr(Obj, Key);
  if A = nil then Exit;
  SetLength(Result, A.Count);
  for i := 0 to A.Count - 1 do
    if A.Items[i] is TJSONArray then
      Result[i] := ArrayToVector(TJSONArray(A.Items[i]));
end;

procedure JPutBool(const Obj: TJSONObject; const Key: string; const Value: Boolean);
begin
  Obj.AddPair(Key, TJSONBool.Create(Value));
end;

procedure JPutInt(const Obj: TJSONObject; const Key: string; const Value: Integer);
begin
  Obj.AddPair(Key, TJSONNumber.Create(Value));
end;

procedure JPutFloat(const Obj: TJSONObject; const Key: string; const Value: Double);
begin
  Obj.AddPair(Key, FloatToJson(Value));
end;

procedure JPutStr(const Obj: TJSONObject; const Key: string; const Value: string);
begin
  Obj.AddPair(Key, Value);
end;

procedure JPutColor(const Obj: TJSONObject; const Key: string; const Value: TAlphaColor);
begin
  Obj.AddPair(Key, AlphaColorToHex(Value));
end;

function VectorToArray(const Values: array of Double): TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(Values) do
    Result.AddElement(FloatToJson(Values[i]));
end;

procedure JPutVector(const Obj: TJSONObject; const Key: string; const Values: array of Double);
begin
  Obj.AddPair(Key, VectorToArray(Values));
end;

procedure JPutMatrix(const Obj: TJSONObject; const Key: string; const Values: TDoubleMatrix);
var
  A: TJSONArray;
  i: Integer;
begin
  A := TJSONArray.Create;
  for i := 0 to High(Values) do
    A.AddElement(VectorToArray(Values[i]));
  Obj.AddPair(Key, A);
end;

end.
