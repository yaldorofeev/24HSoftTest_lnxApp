unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Spin,
  syncobjs;

type

  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    Label1: TLabel;
    Label2: TLabel;
    Memo1: TMemo;
    SpinEdit1: TSpinEdit;
    SpinEdit2: TSpinEdit;
    procedure Button1Click(Sender: TObject);
  private

  public

  end;


type
  TToWrite = record
    order: Integer;
    prime: Integer;
  end;

type
  TPair= record
    x: Integer;
    y: Integer;
  end;

type
  TBarrier = class
  private
    CS: TCriticalSection;
    FReload: boolean;
    FThreadsCount: integer;
    FWaitersCount: integer;
  public
    constructor Create(threadsCount: integer);
    procedure Wait;
  end;


type
  TPrimeWriter = class(TThread)
  private
    FOwnFile: TextFile;
  protected
    procedure Execute; override;
  public
    FSearchBound: integer;
    FOwnPrimeCount: integer;
    FOwnTime: double;
    FFileName: string;
    FThreadsCount: integer;
    FBarrier: TBarrier;
  end;


var
  Form1: TForm1;

  // Critical section for data sharing
  CSPairAccess: TCriticalSection;

    // Critical section for data sharing
  CSPrimeAccess: TCriticalSection;

  // Critical section for data sharing
  CSAAccess: TCriticalSection;

  // Critical section for "Result" file accsess.
  CSWrite: TCriticalSection;

  CommonFile: TextFile;
  WriteThreads: array of TPrimeWriter;
  A: array of integer;

  isPrime: array of boolean;
  pairs: array of TPair;
  globI, globJ, globK: integer;
  foundCount: Integer;

  firstPrimesFlag: boolean;

  LastWrote: Integer;


implementation

{$R *.lfm}

procedure AtkinRun(searchBound: integer; threadsCount: integer; memo: tmemo);
var
  i, j, k: integer;
  Barrier: TBarrier;
begin
  setLength(isPrime, searchBound);
  setLength(pairs, searchBound);
  setLength(WriteThreads, threadsCount);
  globI := 0;
  globJ := 5;
  globK := 1;
  firstPrimesFlag := false;
  foundCount := 0;
  LastWrote := 1;

  AssignFile(CommonFile, 'Result.txt');
  ReWrite(CommonFile);

  CSPairAccess := TCriticalSection.Create();
  CSPrimeAccess := TCriticalSection.Create();
  CSAAccess := TCriticalSection.Create();
  CSWrite := TCriticalSection.Create();

  Barrier := TBarrier.Create(threadsCount);

  for i := 5 to searchBound do
    isPrime[i] := false;

  k := 0;
  for i:=1 to trunc(sqrt(searchBound)) do
    begin
      for j:=1 to trunc(sqrt(searchBound)) do
        begin
          pairs[k].x := i;
          pairs[k].y := j;
          k := k + 1;
        end;
    end;

  for i:=0 to threadsCount - 1 do
    begin
      WriteThreads[i] := TPrimeWriter.Create(true);
      WriteThreads[i].FThreadsCount:= threadsCount;
      WriteThreads[i].FSearchBound:= searchBound;
      WriteThreads[i].FFileName := Format('Thread%d.txt', [i + 1]);
      WriteThreads[i].FBarrier := Barrier;
      WriteThreads[i].Start;
    end;

  //Waiting for threads will be stopped
  for i:=0 to threadsCount - 1 do
    begin
      WriteThreads[i].WaitFor;
      memo.Append(Format('Thread%d finished', [i + 1]));
      memo.Append(Format('Thread%d time is %f', [i + 1, WriteThreads[i].FOwnTime]));
      memo.Append(Format('Thread%d number of written primes is %d', [i + 1, WriteThreads[i].FOwnPrimeCount]));
      WriteThreads[i].DoTerminate;
    end;

end;

{ TBarrier}

constructor TBarrier.Create(threadsCount: integer);
begin
  FThreadsCount := threadsCount;
  FWaitersCount := 0;
  FReload := False;
  CS := TCriticalSection.Create();
end;

procedure TBarrier.Wait;
begin
  CS.Enter;
  FWaitersCount :=  FWaitersCount + 1;
  CS.Leave;
    while true do
      begin
        if FWaitersCount = FThreadsCount then
          begin
            if not FReload then
              begin
                CS.Enter;
                FWaitersCount := 0;
                FReload := True;
                CS.Leave;
              end;
            break;
          end;
      end;
end;

{ TForm1 }

procedure TForm1.Button1Click(Sender: TObject);
begin
  if (spinedit1.Value > 5) and (spinedit2.Value > 1) and (spinedit2.Value < 5) then
    begin
      AtkinRun(spinedit1.Value, spinedit2.Value, memo1);
      //memo1.Append('start');
    end;
end;


{ TPrimeWriter }

procedure TPrimeWriter.Execute;
var
  i, j, k, n: integer;
  x, y, R: Integer;
  toWrites: array of TToWrite;
  LFC: Integer;
  Sta, Sto: int64;
begin
  AssignFile(FOwnFile, FFileName);
  ReWrite(FOwnFile);
  Closefile(FOwnFile);

  FOwnPrimeCount := 0;
  SetLength(toWrites, 0);

  Sta := GetTickCount64;

  while (globI < FSearchBound  + 1) do
    begin
      CSPairAccess.Enter;
      i:= globI;
      globI:= globI + 1;
      x := pairs[i].x;
      y := pairs[i].y;
      CSPairAccess.Leave;

      R := 4 * sqr(x) + sqr(y);
      if (R <= FSearchBound) and ((R mod 12 = 1) or (R mod 12 = 5)) then
        begin
          CSPrimeAccess.Enter;
          isPrime[R] := not isPrime[R];
          CSPrimeAccess.Leave;
        end;

      R := R - sqr(x);
      if (R <= FSearchBound) and (R mod 12 = 7) then
        begin
          CSPrimeAccess.Enter;
          isPrime[R] := not isPrime[R];
          CSPrimeAccess.Leave;
        end;

      R := R - 2 * sqr(y);
      if (x > y) and (R <= FSearchBound) and (R mod 12 = 11) then
        begin
          CSPrimeAccess.Enter;
          isPrime[R] := not isPrime[R];
          CSPrimeAccess.Leave;
        end;
    end;

  //Wait all threads
  FBarrier.Wait;

  while globJ < trunc(sqrt(FSearchBound)) do
    begin

      CSPairAccess.Enter;
      i:= globJ;
      globJ:= globJ + 1;
      CSPairAccess.Leave;

      if isPrime[i] then
        begin
          k := sqr(i);
          n := k;
          while n <= FSearchBound do
            begin
              CSPrimeAccess.Enter;
              isPrime[n] := false;
              CSPrimeAccess.Leave;
              n := n + k;
            end;
        end;
    end;

  if not firstPrimesFlag then
    begin
      CSPrimeAccess.Enter;
      firstPrimesFlag := True;
      isPrime[2] := true;
      isPrime[3] := true;
      CSPrimeAccess.Leave;
    end;

  //Wait all threads
  FBarrier.Wait;

  // Write to files
  while (globK < FSearchBound  + 1) or (Length(toWrites) > 0) do
    begin
      if globK < FSearchBound  + 1 then
        begin
          CSPairAccess.Enter;
          i:= globK;
          globK:= globK + 1;
          CSPairAccess.Leave;


        if isPrime[i] then
          begin
            FOwnPrimeCount := FOwnPrimeCount + 1;
            CSPrimeAccess.Enter;
            foundCount := foundCount + 1;
            LFC := foundCount;
            CSPrimeAccess.Leave;

            // Write to thread*.txt
            Append(FOwnFile);
            Write(FOwnFile, inttostr(i) + ' ');
            Closefile(FOwnFile);

            // Queue toWrites
            SetLength(toWrites, Length(toWrites) + 1);
            toWrites[Length(toWrites) - 1].order := LFC;
            toWrites[Length(toWrites) - 1].prime := i;
          end;
        end;

         // Write to Result.txt from toWrites queue.
      for j:=0 to Length(toWrites) - 1 do
        begin
          if toWrites[j].order = LastWrote then
            begin

              CSWrite.Enter;
              Append(CommonFile);
              Write(CommonFile, inttostr(toWrites[j].prime) + ' ');
              Closefile(CommonFile);
              LastWrote := toWrites[j].order + 1;
              CSWrite.Leave;

              // Dequeue toWrites.
              if Length(toWrites) > 1 then
                begin
                  for k := 1 to Length(toWrites) - 1 do
                    begin
                      toWrites[k - 1] := toWrites[k]
                    end;
                end;
              SetLength(toWrites, Length(toWrites) - 1);
            end
          else break;
        end;
    end;

  Sto := GetTickCount64;
  FOwnTime := Sto-Sta;
end;

end.

